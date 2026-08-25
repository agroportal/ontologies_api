# ontologies_api

ontologies_api provides a RESTful interface for accessing [BioPortal](https://bioportal.bioontology.org/) (an open repository of biomedical ontologies). Supported services include downloads, search, access to terms and concepts, text annotation, and much more.

# Run ontologies_api

## Using OntoPortal api utilities script 
### See help

```bash 
bin/ontoportal help
```

```
Usage:
  ./bin/ontoportal <command> [options]
Commands:
  dev       Start the OntoPortal API development server.
            Examples:
              ./bin/ontoportal dev [shotgun|rackup]
              ./bin/ontoportal dev --api-url http://localhost:9393
              ./bin/ontoportal dev --reset-cache
              ./bin/ontoportal dev --provision-user-only
              ./bin/ontoportal dev --provision-ontology
              ./bin/ontoportal dev --linked-data-path ONTOLOGIES_LINKED_DATA_PATH
              ./bin/ontoportal dev --goo-path GOO_PATH
              ./bin/ontoportal dev  --sparql-client-path SPARQL_CLIENT_PATH

  test      Run tests (all or a specific file).
            Examples:
              ./bin/ontoportal test all
              ./bin/ontoportal test test/controllers/test_users_controller.rb --name=name_of_the_test
            Options:
              --name=TEST_NAME          Run only the test with the given name.
              --backend [vo|fs|ag|gb]   Run the test with specific backend type


  run       Run a command inside the OntoPortal API Docker container.
  help      Show this help message.

Arguments:
  [shotgun|rackup]          Specify the server that used in the dev env (default: shotgun)

Options (dev, test, run):
  --api-url URL             Set the API URL (default: http://localhost:9393).
  --reset-cache             Remove Docker volumes (use with 'dev').
  --provision-user-only     Create only the admin user (no ontology parsing).
  --provision-ontology      Create admin user and parse ontology for use.
  --linked-data-path PATH   Path for ontologies_linked_data.
  --goo-path PATH           Path for goo.
  --sparql-client-path PATH Path for sparql-client.

Notes:
  - 'dev' is for local development with Docker Compose.
  - 'test' supports both individual test files and the 'all' shortcut.
  - 'run' lets you execute arbitrary commands inside the container.
```


### Run dev
```bash 
bin/ontoportal dev 
bin/ontoportal dev [shotgun|rackup]
bin/ontoportal dev --api-url http://localhost:9393
bin/ontoportal dev --reset-cache
bin/ontoportal dev --provision-user-only
bin/ontoportal dev --provision-ontology
bin/ontoportal dev --linked-data-path ONTOLOGIES_LINKED_DATA_PATH
bin/ontoportal dev --goo-path GOO_PATH
bin/ontoportal dev  --sparql-client-path SPARQL_CLIENT_PATH
```

### Run test with a local OntoPortal API
```bash 
bin/ontoportal test all # Run all tests
bin/ontoportal test <path_to_the_test_file> # Run all tests in the test file
bin/ontoportal test <path_to_the_test_file> --name=name_of_the_test # Run single test in the test file
bin/ontoportal test all --backend ag # You can specify the backend type to use for tests
```

## Background jobs (Sidekiq)

API-triggered work runs asynchronously on [Sidekiq](https://sidekiq.org):

- **Submission processing** (`SubmissionProcessWorker`, queue `parsing`): every API endpoint that used
  to push into ncbo_cron's `parseQueue` (submission create, ontology create/patch, `POST /:acronym/pull`,
  admin reprocess) now enqueues a Sidekiq job that delegates to the same
  `NcboCron::Models::OntologySubmissionParser#process_submission` orchestration (parse → index →
  metrics → annotator cache → archive old submissions → report refresh).
- **Emails** (`EmailWorker`, queue `mailers`): all `LinkedData::Utils::Notifier` notifications are
  delivered from Sidekiq instead of blocking the web request on SMTP (see `lib/utils/notifier_async.rb`).

The ncbo_cron daemon keeps its scheduled jobs (its own remote pulls, flush, reports); those still use its
internal `parseQueue` and never overlap with API-created submissions.

### Running the worker

```bash
docker compose up sidekiq        # image gems (also started automatically with the api service)
bin/ontoportal sidekiq           # with your local gem overrides, same options as `dev`
bin/ontoportal sidekiq --linked-data-path ../ontologies_linked_data
```

If you develop with local gem paths, stop the compose `sidekiq` service and use `bin/ontoportal sidekiq`
instead, otherwise the compose worker processes jobs with the image's gem versions.

> **After `--reset-cache` / `--provision-ontology`**: those wipe the docker volumes, and the `app_api`
> volume is re-seeded from the `agroportal/ontologies_api:development` image — code changes that are
> not in the image (a changed Gemfile included) silently disappear from the containers. Rebuild the
> image after code changes (`docker build -t agroportal/ontologies_api:development .`), or re-sync the
> volume: `tar -C . --exclude .git -cf - . | docker run --rm -i -v ontoportal_docker_app_api:/dst alpine tar -C /dst -xf -`

Concurrency: the `parsing` queue runs in a dedicated Sidekiq capsule limited to
`SIDEKIQ_PARSING_CONCURRENCY` (default 1: one OWLAPI parse at a time, like the cron daemon's global
lock); `default`/`mailers` run at `SIDEKIQ_CONCURRENCY` (see `config/sidekiq.rb` / `config/sidekiq.yml`).

### Logs

- Worker process + job logs: `docker compose logs -f sidekiq`, also appended to `log/sidekiq.log`
  inside the `app_api` volume (`docker compose exec sidekiq tail -f log/sidekiq.log`).
- Per-submission parse log (same location ncbo_cron used): `<REPOSITORY_FOLDER>/<ACRONYM>/<submissionId>/parsing.log`
  in the `repository` volume.

### Web UI

Set `SIDEKIQ_WEB_USER` and `SIDEKIQ_WEB_PASSWORD` (see `.env.sample`) and the Sidekiq dashboard is
served at `http://localhost:9393/sidekiq` behind basic auth. Without credentials it is not mounted.

### Redis & durability

Sidekiq state (pending queues, scheduled/retry/dead sets, stats) lives **only** in Redis, in the
dedicated database `REDIS_SIDEKIQ_DB` (default 10) on `REDIS_SIDEKIQ_HOST`. The dev `redis-ut` runs
with `--save "" --appendonly no`: a Redis restart, `FLUSHALL`, or `bin/ontoportal dev --reset-cache`
deletes every queued/retrying job (running jobs finish but are not re-enqueued). The separate DB only
isolates Sidekiq keys from the goo/http/annotator caches (DB 0). **In production point
`REDIS_SIDEKIQ_*` at a persistent Redis (AOF enabled).**

### Retries & failure semantics

- Transient failures (backend unreachable/timeout: Virtuoso/4store, Solr, Redis, remote pull host)
  are retried up to 4 times with exponential backoff.
- Permanent failures (invalid submission, broken/unsupported ontology file, missing upload) are
  **not retried**: the job goes straight to the Dead set in the Web UI, where it can be inspected and
  retried manually after fixing the cause. The submission keeps its `ERROR_*` status either way.
- Processing is guarded by a per-submission Redis lock (24h TTL): the same submission is never parsed
  twice concurrently; a duplicate request re-schedules itself 10 minutes later. Delivery is
  at-least-once: re-runs are safe (RDF generation deletes and reloads the submission graph), but the
  "parsing failed" email can be sent once per retry attempt.

## Manually 
### Prerequisites

- [Ruby 2.x](http://www.ruby-lang.org/en/downloads/) (most recent patch level)
- [rbenv](https://github.com/sstephenson/rbenv) and [ruby-build](https://github.com/sstephenson/ruby-build) (optional)
    - If you need to switch Ruby versions for other projects, you may want to install something like rbenv to manage your Ruby environment.
- [Git](http://git-scm.com/)
- [Bundler](http://gembundler.com/)
    - Install with `gem install bundler` if you don't have it
    - To use local ontologies_linked_data gem: `bundle config local.ontologies_linked_data ~/path_to/ontologies_linked_data/`
- [4store](http://4store.org/)
    - NCBO code relies on 4store as the main datastore. There are several installation options, but the easiest is getting the [binaries](http://4store.org/trac/wiki/Download).
    - For starting, stopping, and restarting 4store easily, you can try setting up [4s-service](https://gist.github.com/4211360)
- [Redis](http://redis.io)
    - Used for caching (HTTP, query caching, Annotator cache)
- [Solr](http://lucene.apache.org/solr/)
    - BioPortal indexes ontology class and property content using Solr (a Lucene-based server)

### Configuring Solr

To configure Solr for ontologies_api usage, modify the example project included with Solr by doing the following:

    cd $SOLR_HOME
    cp example ncbo
    cd $SOLR_HOME/ncbo/solr
    mv collection1 core1
    cd $SOLR_HOME/ncbo/solr/core1/conf
    # Copy NCBO-specific configuration files
    cp `bundle show ontologies_linked_data`/config/solr/solrconfig.xml ./
    cp `bundle show ontologies_linked_data`/config/solr/schema.xml ./
    cd $SOLR_HOME/ncbo/solr
    cp -R core1 core2
    cp `bundle show ontologies_linked_data`/config/solr/solr.xml ./
    # Edit $SOLR_HOME/ncbo/solr/solr.xml
    # Find the following lines:
    # <core name="NCBO1" config="solrconfig.xml" instanceDir="core1" schema="schema.xml" dataDir="data"/>
    # <core name="NCBO2" config="solrconfig.xml" instanceDir="core2" schema="schema.xml" dataDir="data"/>
    # Replace the value of `dataDir` in each line with: 
    # /<your own path to data dir>/core1
    # /<your own path to data dir>/core2
    # Start solr
    java -Dsolr.solr.home=solr -jar start.jar
    # Edit the ontologieS_api/config/environments/{env}.rb file to point to your running instance:
    # http://localhost:8983/solr/NCBO1

### Installing

#### Clone the repository

```
$ git clone git@github.com:ncbo/ontologies_api.git
$ cd ontologies_api
```

#### Install the dependencies

```
$ bundle install
```

#### Create an environment configuration file

```
$ cp config/environments/config.rb.sample config/environments/development.rb
```

[config.rb.sample](https://github.com/ncbo/ontologies_api/blob/1e68882df83cf78cbb78281b1447c303c783e4c2/config/environments/config.rb.sample) can be copied and renamed to match whatever environment you're running, e.g.:

production.rb<br />
development.rb<br />
test.rb

#### Run the unit tests (optional)

Requires a configuration file for the test environment:

```
$ cp config/environments/config.rb.sample config/environments/test.rb
```

Execute the suite of tests from the command line:

```
$ bundle exec rake test 
```

#### Run the application

```
$ bundle exec rackup --port 9393 
```

Once started, the application will be available at localhost:9393.

## Contributing

We encourage contributions! Please check out the [contributing guide](CONTRIBUTING.md) for guidelines on how to proceed.

## Acknowledgements

The National Center for Biomedical Ontology is one of the National Centers for Biomedical Computing supported by the NHGRI, the NHLBI, and the NIH Common Fund under grant U54-HG004028.

## License

[LICENSE.md](LICENSE.md)

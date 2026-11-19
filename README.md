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
```

### Run test with a local OntoPortal API
```bash 
bin/ontoportal test all # Run all tests
bin/ontoportal test <path_to_the_test_file> # Run all tests in the test file
bin/ontoportal test <path_to_the_test_file> --name=name_of_the_test # Run single test in the test file
bin/ontoportal test all --backend ag # You can specify the backend type to use for tests
```


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

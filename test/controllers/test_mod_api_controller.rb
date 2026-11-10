require 'webrick'
require_relative '../test_case'

class TestArtefactsController < TestCase
    def before_suite
        self.backend_4s_delete
        self.class._create_onts
    end

    def after_suite
        self.backend_4s_delete
    end

    def self._create_onts
        options = {
            ont_count: 2,
            submission_count: 2,
            submissions_to_process: [1],
            process_submission: true,
            random_submission_count: false,
            acronym: "TST"
        }
        # this will create 2 ontologies (TST-0, TST-1) with 2 submissions each
        @@num_onts_created, @@created_ont_acronyms, @@ontologies = LinkedData::SampleData::Ontology.create_ontologies_and_submissions(options)
        @@ontology_0, @@ontology_0_acronym = @@ontologies[0], @@created_ont_acronyms[0]
        type = LinkedData::Models::Class.class_rdf_type(@@ontologies[0].latest_submission)
        @@ontology_type = type == RDF::OWL[:Class] ? "OWL" : "SKOS"
        @@page = 2
        @@pagesize = 1
        @@ontologies[0].latest_submission.index_all(Logger.new($stdout))
    end

    def test_home_controller
        get "/"
        assert last_response.ok?
        catalog_data = MultiJson.load(last_response.body)

        assert catalog_data.key?("links")
        assert catalog_data.delete("links").is_a?(Hash)
        assert catalog_data.key?("@context")
        assert catalog_data.delete("@context").is_a?(Hash)

        expected_data = {
            "acronym"=>"OntoPortal",
            "title"=>"OntoPortal",
            "color"=>"#5499A3",
            "description"=>"Welcome to OntoPortal Appliance, your ontology repository for your ontologies",
            "logo"=>"https://ontoportal.org/images/logo.png",
            "identifier"=>nil,
            "status"=>"alpha",
            "language"=>["English"],
            "accessRights"=>"public",
            "license"=>"https://opensource.org/licenses/BSD-2-Clause",
            "rightsHolder"=>nil,
            "landingPage"=>"http://bioportal.bioontology.org",
            "keyword"=>[],
            "bibliographicCitation"=>[],
            "created"=>nil,
            "modified"=>nil,
            "contactPoint"=>[],
            "creator"=>[],
            "contributor"=>[],
            "publisher"=>[],
            "subject"=>[],
            "coverage"=>[],
            "createdWith"=>[],
            "accrualMethod"=>[],
            "accrualPeriodicity"=>[],
            "wasGeneratedBy"=>[],
            "accessURL"=>"http://data.bioontology.org/",
            "numberOfArtefacts"=>2,
            "federated_portals"=>[{"name"=>"agroportal", "api"=>"http://data.agroportal.lirmm.fr", "ui"=>"http://agroportal.lirmm.fr", "color"=>"#3cb371"}],
            "fundedBy"=>[{"img_src"=>"https://ontoportal.org/images/logo.png", "url"=>"https://ontoportal.org/"}],
            "sampleQueries"=>[],
            "@id"=>"http://data.bioontology.org/",
            "@type"=>"https://w3id.org/mod#SemanticArtefactCatalog"
        }

        assert_equal expected_data, catalog_data
    end

    # Catalogs saved before Ruby 3.4 hold the old Hash#inspect format
    def test_home_controller_legacy_hash_format
        get "/"
        catalog = LinkedData::Models::SemanticArtefactCatalog.all.first
        catalog.bring_remaining
        original = [catalog.federated_portals, catalog.fundedBy]

        catalog.federated_portals = ['{:name=>"agroportal", :api=>"http://data.agroportal.lirmm.fr", :ui=>"http://agroportal.lirmm.fr", :apikey=>"DUMMY_API_KEY_123456", :color=>"#3cb371"}']
        catalog.fundedBy = ['{:img_src=>"https://ontoportal.org/images/logo.png", :url=>"https://ontoportal.org/"}']
        catalog.save

        get "/"
        catalog_data = MultiJson.load(last_response.body)
        assert_equal [{"name"=>"agroportal", "api"=>"http://data.agroportal.lirmm.fr", "ui"=>"http://agroportal.lirmm.fr", "color"=>"#3cb371"}], catalog_data["federated_portals"]
        assert_equal [{"img_src"=>"https://ontoportal.org/images/logo.png", "url"=>"https://ontoportal.org/"}], catalog_data["fundedBy"]
    ensure
        unless catalog.nil?
            catalog.federated_portals, catalog.fundedBy = original
            catalog.save
        end
    end

    
    def test_all_artefacts
        route = '/mod-api/artefacts'
        get "#{route}?page=#{@@page}&pagesize=#{@@pagesize}"
        assert last_response.ok?
        artefacts_page_data = MultiJson.load(last_response.body)
        validate_hydra_page(route, artefacts_page_data)
        assert_equal @@num_onts_created, artefacts_page_data["totalItems"]
        artefacts_page_data["member"].each do |artefact|
            assert @@created_ont_acronyms.include?(artefact["acronym"])
        end
    end

    def test_one_artefact
        route = "/mod-api/artefacts/#{@@ontology_0_acronym}"
        get route
        assert last_response.ok?
        artefact_data = MultiJson.load(last_response.body)
        assert_equal @@ontology_0_acronym, artefact_data["acronym"]
    end

    def test_all_distributions
        route = "/mod-api/artefacts/#{@@ontology_0_acronym}/distributions"
        get "#{route}?page=#{@@page}&pagesize=#{@@pagesize}"
        assert last_response.ok?
        dists_page_data = MultiJson.load(last_response.body)
        validate_hydra_page(route, dists_page_data)
        assert_equal 2, dists_page_data["totalItems"]
    end

    def test_one_distribution
        route = "/mod-api/artefacts/#{@@ontology_0_acronym}/distributions/1"
        get route
        assert last_response.ok?
        dist_data = MultiJson.load(last_response.body)
        assert_equal 1, dist_data["distributionId"]
    end

    def test_latest_distribution
        route = "/mod-api/artefacts/#{@@ontology_0_acronym}/distributions/latest"
        get route
        assert last_response.ok?
        dist_data = MultiJson.load(last_response.body)
        assert_equal 2, dist_data["distributionId"]
    end

    def test_resources
        total_count = total_resources_count
        route =  "/mod-api/artefacts/#{@@ontology_0_acronym}/resources"
        get "#{route}?page=#{@@page}&pagesize=#{@@pagesize}"
        assert last_response.ok?
        resources_page_data = MultiJson.load(last_response.body)
        validate_hydra_page(route, resources_page_data)
        assert_equal total_count, resources_page_data["totalItems"]
    end

    def test_one_resource
        uri = "http://bioontology.org/ontologies/BiomedicalResourceOntology.owl#Modular_Component"
        route = "/mod-api/artefacts/#{@@ontology_0_acronym}/resources/#{CGI.escape(uri)}"
        get route
        assert last_response.ok?
        resource_data = MultiJson.load(last_response.body)
        assert_equal uri, resource_data["@id"]
    end

    %w[classes individuals].each do |resource|
        define_method("test_#{resource}") do
            route = "/mod-api/artefacts/#{@@ontology_0_acronym}/resources/#{resource}"
            get "#{route}?page=#{@@page}&pagesize=#{@@pagesize}"
            assert last_response.ok?
            page_data = MultiJson.load(last_response.body)
            if @@ontology_type == "OWL"
                resource_count = model_count(resource_model[resource], @@ontology_0.latest_submission)
                validate_hydra_page(route, page_data)
                assert_equal resource_count, page_data["totalItems"]
            else
                validate_hydra_page(route, page_data)
            end
        end
    end
    
    %w[concepts schemes collections labels].each do |resource|
        define_method("test_#{resource}") do
            route = "/mod-api/artefacts/#{@@ontology_0_acronym}/resources/#{resource}"
            get "#{route}?page=#{@@page}&pagesize=#{@@pagesize}"
            assert last_response.ok?
            page_data = MultiJson.load(last_response.body)
            if @@ontology_type == "SKOS"
                resource_count = model_count(resource_model[resource], @@ontology_0.latest_submission)
                validate_hydra_page(route, page_data)
                assert_equal resource_count, page_data["totalItems"]
            else
                validate_hydra_page(route, page_data)
            end
        end
    end
    
    def test_properties
        route = "/mod-api/artefacts/#{@@ontology_0_acronym}/resources/properties" 
        get "#{route}?page=#{@@page}&pagesize=#{@@pagesize}"
        assert last_response.ok?
        properties_page_data = MultiJson.load(last_response.body)
        properties_count = @@ontology_0.properties.count
        validate_hydra_page(route, properties_page_data)
        assert_equal properties_count, properties_page_data["totalItems"]
    end
    
    def test_records
        route = "/mod-api/records"
        get "#{route}?page=#{@@page}&pagesize=#{@@pagesize}"
        assert last_response.ok?
        records_page_data = MultiJson.load(last_response.body)
        validate_hydra_page(route, records_page_data)
        assert_equal @@num_onts_created, records_page_data["totalItems"]
        records_page_data["member"].each do |artefact|
            assert @@created_ont_acronyms.include?(artefact["acronym"])
        end
    end
    
    def test_one_record
        get "/mod-api/records/#{@@ontology_0_acronym}"
        assert last_response.ok?
        record_data_from_records = MultiJson.load(last_response.body)
        assert_equal @@ontology_0_acronym, record_data_from_records["acronym"]
        
        get "/mod-api/artefacts/#{@@ontology_0_acronym}/record"
        assert last_response.ok?
        record_data_from_artefact = MultiJson.load(last_response.body)
        assert_equal @@ontology_0_acronym, record_data_from_artefact["acronym"]

        assert_equal record_data_from_artefact, record_data_from_records
    end

    def test_search_content
        route = "/mod-api/search/content"
        get "#{route}?query=modular"
        assert last_response.ok?
        search_page_data = MultiJson.load(last_response.body)
        validate_hydra_page(route, search_page_data)
    end

    def test_search_metadata
        route = "/mod-api/search/metadata"
        get "#{route}?query=TST-0"
        assert last_response.ok?
        search_page_data = MultiJson.load(last_response.body)
        validate_hydra_page(route, search_page_data)
    end

    def test_swagger_documentation
        get "/openapi.json"
        assert last_response.ok?
        assert_equal 'application/json', last_response.content_type
        
        doc = JSON.parse(last_response.body)
        
        assert_equal '3.0.0', doc['openapi']
        assert_equal 'MOD-API Documentation', doc['info']['title']
        assert_equal '1.0.0', doc['info']['version']
        assert_equal 'Ontoportal MOD-API documentation', doc['info']['description']
        
        expected_paths = [
            '/',
            '/mod-api/artefacts',
            '/mod-api/artefacts/{artefactID}',
            '/mod-api/artefacts/{artefactID}/distributions',
            '/mod-api/artefacts/{artefactID}/distributions/latest',
            '/mod-api/artefacts/{artefactID}/distributions/{distributionID}',
            '/mod-api/artefacts/{artefactID}/record',
            '/mod-api/artefacts/{artefactID}/resources',
            '/mod-api/artefacts/{artefactID}/resources/classes',
            '/mod-api/artefacts/{artefactID}/resources/classes/{uri}',
            '/mod-api/artefacts/{artefactID}/resources/collections',
            '/mod-api/artefacts/{artefactID}/resources/collections/{uri}',
            '/mod-api/artefacts/{artefactID}/resources/concepts',
            '/mod-api/artefacts/{artefactID}/resources/concepts/{uri}',
            '/mod-api/artefacts/{artefactID}/resources/individuals',
            '/mod-api/artefacts/{artefactID}/resources/individuals/{uri}',
            '/mod-api/artefacts/{artefactID}/resources/labels',
            '/mod-api/artefacts/{artefactID}/resources/labels/{uri}',
            '/mod-api/artefacts/{artefactID}/resources/properties',
            '/mod-api/artefacts/{artefactID}/resources/properties/{uri}',
            '/mod-api/artefacts/{artefactID}/resources/schemes',
            '/mod-api/artefacts/{artefactID}/resources/schemes/{uri}',
            '/mod-api/artefacts/{artefactID}/resources/{uri}',
            '/mod-api/records',
            '/mod-api/records/{artefactID}',
            '/mod-api/search',
            '/mod-api/search/content',
            '/mod-api/search/metadata'
        ]
        assert_equal expected_paths.sort, doc['paths'].keys.sort
    end

    private

    def validate_hydra_page(route, page_data)
        assert page_data.key?('@context')
        assert page_data.key?('@id')
        assert page_data.key?('@type')
        assert page_data.key?("totalItems")
        assert page_data.key?('itemsPerPage')
        assert page_data.key?('view')
        assert page_data['view'].key?('@id')
        assert page_data['view'].key?('firstPage')
        assert page_data['view'].key?('previousPage')
        assert page_data['view'].key?('nextPage')
        assert page_data['view'].key?('lastPage')
        assert page_data.key?('member')
        assert page_data["member"].is_a?(Array)
    end

    def total_resources_count
        total_count = 0
        resource_model.values.uniq.each do |model|
            total_count += model_count(model, @@ontology_0.latest_submission)
        end
        total_count += @@ontology_0.properties.count
        return total_count
    end

    def resource_model
        {
          "classes" => LinkedData::Models::Class,
          "concepts" => LinkedData::Models::Class,
          "individuals" => LinkedData::Models::Instance,
          "schemes" => LinkedData::Models::SKOS::Scheme,
          "collections" => LinkedData::Models::SKOS::Collection,
          "labels" => LinkedData::Models::SKOS::Label
        }
    end

    def model_count(model, sub)
        model.where.in(sub).count
    end

end
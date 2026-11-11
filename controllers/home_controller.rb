require 'haml'

class HomeController < ApplicationController

  namespace '/' do

    doc('Catalog', 'Get the semantic artefact catalogue') do
      default_params(display: true)
      default_responses(success: true)
    end
    get do
      catalog_class = LinkedData::Models::SemanticArtefactCatalog
      catalog = catalog_class.all.first || create_catalog
      check_last_modified(catalog)

      attributes_to_include =  includes_param[0] == :all ? catalog_class.attributes(:all) : catalog_class.goo_attrs_to_load(includes_param)
      catalog.bring(*attributes_to_include)
      catalog.federated_portals = safe_parse(catalog.federated_portals) { |item| item.delete('apikey') unless current_user&.admin? } if catalog.loaded_attributes.include?(:federated_portals)
      catalog.fundedBy = safe_parse(catalog.fundedBy) if catalog.loaded_attributes.include?(:fundedBy) 
      reply catalog
    end

    patch do
      error 401, "Unauthorized: Admin access required to update the catalog" unless current_user&.admin?
      catalog = LinkedData::Models::SemanticArtefactCatalog.where.first
      error 422, "There is no catalog configs in the triple store" if catalog.nil?
      populate_from_params(catalog, params)
      if catalog.valid?
        catalog.save
        status 200
        reply catalog
      else
        error 422, catalog.errors
      end
    end

    get "documentation" do
      @metadata_all = get_metadata_all.sort { |a, b| a[0].name <=> b[0].name }
      haml "documentation/documentation".to_sym, :layout => "documentation/layout".to_sym
    end

    private

    def create_catalog
      catalog = nil
      catalogs = LinkedData::Models::SemanticArtefactCatalog.all
      if catalogs.nil? || catalogs.empty?
          catalog = instance_from_params(LinkedData::Models::SemanticArtefactCatalog, {})
          if catalog.valid?
              catalog.save
          else
              error 422, catalog.errors
          end
      end
      catalog
    end
    
    # Items are stored as Hash#inspect, whose format changed in Ruby 3.4:
    #   {:name=>"agroportal"}  before 3.4, still in existing triple stores
    #   {name: "agroportal"}   from 3.4
    def safe_parse(value)
      return nil unless value

      parse_item = ->(item) {
        begin
          parsed = JSON.parse(
            item.gsub(/([{,]\s*)(\w+): /, '\1"\2": ').gsub(/:(\w+)=>/, '"\1":').gsub('=>', ':').gsub('\"', '"')
          )
          yield(parsed) if block_given?
          parsed
        rescue JSON::ParserError => e
          nil
        end
      }

      if value.is_a?(Array)
        value.map { |item| parse_item.call(item) }
      else
        parse_item.call(value)
      end
    end

  end
end

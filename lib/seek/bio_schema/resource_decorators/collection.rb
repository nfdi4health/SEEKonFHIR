module Seek
  module BioSchema
    module ResourceDecorators
      class Collection < CreativeWork
        associated_items has_part: :schema_enabled_assets
        schema_mappings has_part: :hasPart

        def schema_type
          'Collection'
        end

        def conformance
          'https://schema.org/Collection'
        end

        def schema_enabled_assets
          assets.reject(&:blank?).select(&:schema_org_supported?)
        end
      end
    end
  end
end

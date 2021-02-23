module Seek
  module BioSchema
    module ResourceDecorators
      # Decorator that provides extensions for a Workflow
      class Workflow < CreativeWork
        associated_items sd_publisher: 'contributors'

        schema_mappings sd_publisher: :sdPublisher,
                        version: :version,
                        image: :image,
                        programming_language: :programmingLanguage,
                        producer: :producer,
                        inputs: :input,
                        outputs: :output,
                        license: :license

        def contributors
          [contributor]
        end

        def image
          return unless resource.diagram_exists?
          diagram_workflow_url(resource, version: resource.version, host: Seek::Config.site_base_host)
        end

        def schema_type
          ['File', 'SoftwareSourceCode', 'ComputationalWorkflow']
        end

        def programming_language
          resource.workflow_class&.extractor_class.ro_crate_metadata
        end

        def inputs
          formal_parameters(resource.inputs, 'inputs')
        end

        def outputs
          formal_parameters(resource.outputs, 'outputs')
        end

        def license
          resource.license
        end

        private

        def formal_parameters(properties, group_name)
          if self.title
            wf_name = self.title.downcase.gsub(/[^0-9a-z]/i, '_')
          else
            wf_name = 'dummy'
          end
          properties.collect do |property|
            {
              "@type": 'FormalParameter',
              "@id": "##{wf_name}-#{group_name}-#{property.id}",
              name: property.name || property.id
            }
          end
        end
      end
    end
  end
end

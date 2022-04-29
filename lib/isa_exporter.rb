# noinspection ALL
module IsaExporter
	class Exporter
		def initialize(investigation)
			@investigation = investigation
			@OBJECT_MAP = {}
		end

		def convert_investigation
			isa_investigation = {}
			isa_investigation[:identifier] = nil # @investigation.id
			isa_investigation[:title] = @investigation.title
			isa_investigation[:description] = @investigation.description
			isa_investigation[:submissionDate] = nil # @investigation.created_at.to_date.iso8601
			isa_investigation[:publicReleaseDate] = nil # @investigation.created_at.to_date.iso8601
			isa_investigation[:ontologySourceReferences] = convert_ontologies
			isa_investigation[:filename] = "#{@investigation.title}.txt"
			isa_investigation[:comments] = [
				{ name: 'ISAjson export time', value: Time.now.utc.iso8601 },
				{ name: 'SEEK Project name', value: @investigation.projects.first.title },
				{
					name: 'SEEK Project ID',
					value: "#{Seek::Config.site_base_host}/single_pages/#{@investigation.projects.first.id}"
				},
				{ name: 'SEEK Investigation ID', value: @investigation.id }
			]

			publications = []
			@investigation.publications.each { |p| publications << convert_publication(p) }
			isa_investigation[:publications] = publications

			people = []
			@investigation.related_people.each { |p| people << convert_person(p) }
			isa_investigation[:people] = people

			studies = []
			@investigation.studies.each { |s| studies << convert_study(s) }
			isa_investigation[:studies] = studies

			@OBJECT_MAP[:investigation] = isa_investigation

			isa_investigation
		end

		def convert_study(study)
			isa_study = {}
			isa_study[:identifier] = nil # study.id
			isa_study[:title] = study.title
			isa_study[:description] = study.description
			isa_study[:submissionDate] = nil # study.created_at.to_date.iso8601
			isa_study[:publicReleaseDate] = nil # study.created_at.to_date.iso8601
			isa_study[:filename] = "#{study.title}.txt"
			isa_study[:comments] = [
				{ name: 'SEEK ID', value: "studies/#{study.id}" },
				{ name: 'SEEK creation date', value: study.created_at.to_date.iso8601 }
			]

			publications = []
			study.publications.each { |p| publications << convert_publication(p) }
			isa_study[:publications] = publications

			people = []
			study.related_people.each { |p| people << convert_person(p) }
			isa_study[:people] = people
			isa_study[:studyDesignDescriptors] = []
			isa_study[:characteristicCategories] = convert_characteristic_categories(study)
			isa_study[:materials] = {
				sources: convert_materials_sources(study.sample_types.first),
				samples: convert_materials_samples(study.sample_types.second)
			}

			protocols = []

			with_tag_protocol_study = study.sample_types.second.sample_attributes.detect { |sa| sa.isa_tag&.isa_protocol? }
			with_tag_parameter_value_study =
				study.sample_types.second.sample_attributes.select { |sa| sa.isa_tag&.isa_parameter_value? }
			raise "Protocol ISA tag not found in study #{study.id}" if with_tag_protocol_study.blank?

			protocols << convert_protocol(study.sop, study.id, with_tag_protocol_study, with_tag_parameter_value_study)

			study.assays.each do |a|
				# There should be only one attribute with isa_tag == protocol
				with_tag_protocol = a.sample_type.sample_attributes.detect { |sa| sa.isa_tag&.isa_protocol? }
				with_tag_parameter_value = a.sample_type.sample_attributes.select { |sa| sa.isa_tag&.isa_parameter_value? }
				raise "Protocol ISA tag not found in assay #{a.id}" if with_tag_protocol.blank?

				protocols << convert_protocol(a.sops.first, a.id, with_tag_protocol, with_tag_parameter_value)
			end
			isa_study[:protocols] = protocols

			isa_study[:processSequence] = convert_process_sequence(study.sample_types.second, study.sop)

			isa_study[:assays] = [convert_assays(study.assays)]

			isa_study[:factors] = []
			isa_study[:unitCategories] = []

			isa_study
		end

		def convert_annotation(term_uri)
			isa_annotation = {}
			term = term_uri.split('#')[1]
			isa_annotation[:annotationValue] = term
			isa_annotation[:termAccession] = term_uri
			isa_annotation[:termSource] = 'jerm_ontology'
			isa_annotation
		end

		def convert_assays(assays)
			all_sample_types = assays.map { |a| a.sample_type }
			all_samples = all_sample_types.map { |s| s.samples }.flatten
			first_assay = assays.detect { |s| s.position == 0 }

			isa_assay = {}
			isa_assay['@id'] = "#assay/#{assays.pluck(:id).join('_')}"
			isa_assay[:filename] = 'a_assays.txt' # assay&.sample_type&.isa_template&.title
			isa_assay[:measurementType] = { annotationValue: nil, termSource: nil, termAccession: nil }
			isa_assay[:technologyType] = { annotationValue: nil, termSource: nil, termAccession: nil }
			isa_assay[:technologyPlatform] = nil
			isa_assay[:characteristicCategories] = convert_characteristic_categories(nil, assays)
			isa_assay[:materials] = {
				# Here, the first assay's samples will be enough
				samples:
					first_assay.samples.map { |s| find_sample_origin([s]) }.flatten.uniq.map { |s| { '@id': "#sample/#{s}" } }, # the samples from study level that are referenced in this assay's samples,
				otherMaterials: convert_other_materials(all_sample_types)
			}
			isa_assay[:processSequence] = assays.map { |a| convert_process_sequence(a.sample_type, a.sops.first) }.flatten
			isa_assay[:dataFiles] = convert_data_files(all_sample_types)
			isa_assay[:unitCategories] = []
			isa_assay
		end

		def convert_person(person)
			isa_person = { '@id': "#people/#{person.id}" }
			isa_person[:lastName] = person.last_name
			isa_person[:firstName] = person.first_name
			isa_person[:midInitials] = ''
			isa_person[:email] = person.email
			isa_person[:phone] = person.phone
			isa_person[:fax] = nil
			isa_person[:address] = nil
			isa_person[:affiliation] = nil
			roles = {}
			roles[:termAccession] = nil
			roles[:termSource] = nil
			roles[:annotationValue] = nil
			isa_person[:roles] = [roles]
			isa_person[:comments] = [{ '@id': nil, value: nil, name: nil }]
			isa_person
		end

		def convert_publication(publication)
			isa_publication = {}
			isa_publication[:pubMedID] = publication.pubmed_id
			isa_publication[:doi] = publication.doi
			status = {}
			status[:termAccession] = nil
			status[:termSource] = nil
			status[:annotationValue] = nil
			isa_publication[:status] = status
			isa_publication[:title] = publication.title
			isa_publication[:author_list] = publication.authors.map { |a| a.full_name }.join(', ')

			publication
		end

		def convert_ontologies
			client = Ebi::OlsClient.new
			source_ontologies = []
			sample_types = @investigation.studies.map { |s| s.sample_types } + @investigation.assays.map { |a| a.sample_type }
			sample_types.flatten.each do |sa|
				sa.sample_attributes.each do |atr|
					source_ontologies << atr.sample_controlled_vocab.source_ontology if atr.sample_attribute_type.ontology?
				end
			end
			source_ontologies.uniq.map { |s| client.fetch_ontology_reference(s) }
		end

		def convert_protocol(sop, id, protocol, parameter_values)
			isa_protocol = {}

			#   sop = assay.sops.first
			isa_protocol['@id'] = "#protocol/#{sop.id}_#{id}"
			isa_protocol[:name] = protocol.title # sop.title

			ontology = get_ontology_details(protocol, protocol.title, false)

			isa_protocol[:protocolType] = {
				annotationValue: protocol.title,
				termAccession: ontology[:termAccession],
				termSource: ontology[:termSource]
			}
			isa_protocol[:description] = sop.description
			isa_protocol[:uri] = ontology[:termAccession]
			isa_protocol[:version] = nil
			isa_protocol[:parameters] =
				parameter_values.map do |parameter_value|
					parameter_value_ontology = get_ontology_details(parameter_value, parameter_value.title, false)
					{
						'@id': "#parameter/#{parameter_value.id}",
						parameterName: {
							annotationValue: parameter_value.title,
							termAccession: parameter_value_ontology[:termAccession],
							termSource: parameter_value_ontology[:termSource]
						}
					}
				end
			isa_protocol[:components] = [
				{ componentName: nil, componentType: { annotationValue: nil, termSource: nil, termAccession: nil } }
			]

			isa_protocol
		end

		def convert_materials_sources(sample_type)
			with_tag_source = sample_type.sample_attributes.detect { |sa| sa.isa_tag&.isa_source? }
			with_tag_source_characteristic =
				sample_type.sample_attributes.select { |sa| sa.isa_tag&.isa_source_characteristic? }

			# attributes = sample_type.sample_attributes.select{ |sa| sa.isa_tag&.isa_source_characteristic? }
			sample_type.samples.map do |s|
				{
					'@id': "#source/#{s.id}",
					name: s.get_attribute_value(with_tag_source),
					characteristics: convert_characteristics(s, with_tag_source_characteristic)
				}
			end
		end

		def convert_materials_samples(sample_type)
			with_tag_sample = sample_type.sample_attributes.detect { |sa| sa.isa_tag&.isa_sample? }
			with_tag_sample_characteristic =
				sample_type.sample_attributes.select { |sa| sa.isa_tag&.isa_sample_characteristic? }
			with_type_seek_sample_multi = sample_type.sample_attributes.detect(&:seek_sample_multi?)
			sample_type.samples.map do |s|
				{
					'@id': "#sample/#{s.id}",
					name: s.get_attribute_value(with_tag_sample),
					derivesFrom: extract_sample_ids(s.get_attribute_value(with_type_seek_sample_multi), 'source'),
					characteristics: convert_characteristics(s, with_tag_sample_characteristic),
					factorValues: [
						{
							category: {
								'@id': nil
							},
							value: {
								annotationValue: nil,
								termSource: nil,
								termAccession: nil
							},
							unit: nil
						}
					]
				}
			end
		end

		def convert_characteristics(sample, attributes)
			attributes.map do |c|
				value = sample.get_attribute_value(c)
				ontology = get_ontology_details(c, value, true)
				{
					category: {
						'@id': "#characteristic_category/#{c.title}"
					},
					value: {
						annotationValue: value,
						termSource: ontology[:termSource],
						termAccession: ontology[:termAccession]
					},
					unit: nil
				}
			end
		end

		def convert_characteristic_categories(study = nil, assays = nil)
			attributes = []
			if study
				attributes = study.sample_types.map { |s| s.sample_attributes }.flatten
				attributes =
					attributes.select { |sa| sa.isa_tag&.isa_source_characteristic? || sa.isa_tag&.isa_sample_characteristic? }
			elsif assays
				attributes = assays.map { |a| a.sample_type.sample_attributes }.flatten
				attributes = attributes.select { |sa| sa.isa_tag&.isa_other_material_characteristic? }
			end
			attributes.map do |s|
				ontology = get_ontology_details(s, s.title, false)
				{
					'@id': "#characteristic_category/#{s.title}",
					characteristicType: {
						annotationValue: s.title,
						termAccession: ontology[:termAccession],
						termSource: ontology[:termSource]
					}
				}
			end
		end

		def convert_process_sequence(sample_type, sop)
			# This method is meant to be used for both Studies and Assays
			return [] unless sample_type.samples.any?

			with_tag_isa_parameter_value = get_values(sample_type)
			with_tag_protocol = detect_protocol(sample_type)
			with_type_seek_sample_multi = detect_sample_multi(sample_type)
			type = 'source'
			type = get_derived_from_type(sample_type) if sample_type.assays.any?

			# Convention : The sample_types of studies don't have assay
			sample_type.samples.map do |s|
				{
					'@id': "#process/#{with_tag_protocol.title}/#{s.id}",
					name: nil,
					executesProtocol: {
						'@id': "#protocol/#{sop.id}" + (s.assays.any? ? "_#{s.assays.first.id}" : '')
					},
					parameterValues: convert_parameter_values(s, with_tag_isa_parameter_value),
					performer: nil,
					date: nil,
					previousProcess: previous_process(s),
					nextProcess: next_process(s),
					inputs: extract_sample_ids(s.get_attribute_value(with_type_seek_sample_multi), type),
					outputs: process_sequence_output(s)
				}
			end
		end

		def convert_data_files(sample_types)
			st = sample_types.detect { |s| detect_data_file(s) }
			return [] unless st

			with_tag_data_file = detect_data_file(st)
			with_tag_data_file_comment = select_data_file_comment(st)
			return [] unless with_tag_data_file

			st.samples.map do |s|
				{
					'@id': "#data/#{s.id}",
					name: s.get_attribute_value(with_tag_data_file),
					type: with_tag_data_file.title,
					comments: with_tag_data_file_comment.map { |d| { name: d.title, value: s.get_attribute_value(d) } }
				}
			end
		end

		def convert_other_materials(sample_types)
			all_attributes = sample_types.map { |s| s.sample_attributes }.flatten
			isa_other_material_sample_types =
				sample_types.select { |s| s.sample_attributes.detect { |sa| sa.isa_tag&.isa_other_material? } }

			other_materials = []
			isa_other_material_sample_types.each do |st|
				with_tag_isa_other_material = st.sample_attributes.detect { |sa| sa.isa_tag&.isa_other_material? }
				return [] unless with_tag_isa_other_material

				with_type_seek_sample_multi = st.sample_attributes.detect(&:seek_sample_multi?)
				raise 'Defective ISA other_materials!' unless with_type_seek_sample_multi

				with_tag_isa_other_material_characteristics =
					st.sample_attributes.select { |sa| sa.isa_tag&.isa_other_material_characteristic? }

				type = get_derived_from_type(st)
				raise 'Defective ISA process_sequence!' unless type

				other_materials +=
					st
						.samples
						.map do |s|
							{
								'@id': "#other_material/#{s.id}",
								name: s.get_attribute_value(with_tag_isa_other_material),
								type: with_tag_isa_other_material.title,
								characteristics: convert_characteristics(s, with_tag_isa_other_material_characteristics),
								# It can sometimes be other_material or sample!!!! SHOULD BE DYNAMIC
								derivesFrom: extract_sample_ids(s.get_attribute_value(with_type_seek_sample_multi), type)
							}
						end
						.flatten
			end
			other_materials
		end

		def export
			convert_investigation
			@OBJECT_MAP.to_json
		end

		private

		def detect_sample(sample_type)
			sample_type.sample_attributes.detect { |sa| sa.isa_tag&.isa_sample? }
		end

		def detect_source(sample_type)
			sample_type.sample_attributes.detect { |sa| sa.isa_tag&.isa_source? }
		end

		def detect_protocol(sample_type)
			sample_type.sample_attributes.detect { |sa| sa.isa_tag&.isa_protocol? }
		end

		def get_values(sample_type)
			sample_type.sample_attributes.select { |sa| sa.isa_tag&.isa_parameter_value? }
		end

		def detect_data_file(sample_type)
			sample_type.sample_attributes.detect { |sa| sa.isa_tag&.isa_data_file? }
		end

		def select_data_file_comment(sample_type)
			sample_type.sample_attributes.select { |sa| sa.isa_tag&.isa_data_file_comment? }
		end

		def detect_other_material(sample_type)
			sample_type.sample_attributes.detect { |sa| sa.isa_tag&.isa_other_material? }
		end

		def detect_sample_multi(sample_type)
			sample_type.sample_attributes.detect(&:seek_sample_multi?)
		end

		def next_process(sample)
			# return { "@id": nil } for studies
			return { '@id': nil } if sample.sample_type.assays.blank?

			sample_type = sample.linking_samples.first&.sample_type
			return nil unless sample_type

			protocol = detect_protocol(sample_type)
			sample_type && protocol ? { '@id': "#process/#{detect_protocol(sample_type).title}/#{sample.id}" } : nil
		end

		def previous_process(sample)
			sample_type = sample.linked_samples.first&.sample_type
			return nil unless sample_type

			protocol = detect_protocol(sample_type)

			# if there's no protocol, it means the previous sample type is source
			sample_type && protocol ? { '@id': "#process/#{protocol.title}/#{sample.id}" } : nil
		end

		def process_sequence_output(sample)
			prefix = 'sample'
			if sample.sample_type.isa_template.level == 'assay'
				if detect_other_material(sample.sample_type)
					prefix = 'other_material'
				elsif detect_data_file(sample.sample_type)
					prefix = 'data_file'
				else
					raise 'Defective ISA process!'
				end
			end
			{ '@id': "##{prefix}/#{sample.id}" }
		end

		def convert_parameter_values(sample, with_tag_isa_parameter_value)
			with_tag_isa_parameter_value.map do |p|
				value = sample.get_attribute_value(p)
				ontology = get_ontology_details(p, value, true)
				{
					category: {
						'@id': "#parameter/#{p.id}"
					},
					value: {
						annotationValue: value,
						termSource: ontology[:termSource],
						termAccession: ontology[:termAccession]
					},
					unit: nil
				}
			end
		end

		def extract_sample_ids(obj, type)
			Array.wrap(obj).map { |item| { '@id': "##{type}/#{item[:id]}" } }
		end

		def get_ontology_details(sample_attribute, label, vocab_term)
			is_ontology = sample_attribute.sample_attribute_type.ontology?
			iri = ''
			if is_ontology
				iri =
					if vocab_term
						sample_attribute.sample_controlled_vocab.sample_controlled_vocab_terms.find_by_label(label)&.iri
					else
						sample_attribute.sample_controlled_vocab.ols_root_term_uri
					end
			end
			{
				termAccession: is_ontology ? iri : nil,
				termSource: is_ontology ? sample_attribute.sample_controlled_vocab.source_ontology : nil
			}
		end

		# This method finds the source sample (sample_collection/samples of 2nd sample_type of the study) of a sample
		# The samples declared in the study level and being used in the stream of the current sample
		def find_sample_origin(sample_list)
			parent_samples = []
			while sample_list.any?
				temp = []
				sample_list.each do |sample|
					if sample.linked_samples.any?
						temp += sample.linked_samples
					else
						parent_samples << sample
					end
				end
				sample_list = temp
			end
			parent_samples.map { |s| s.id }.uniq
		end

		def random_string(len)
			(0...len).map { ('a'..'z').to_a[rand(26)] }.join
		end

		def get_derived_from_type(sample_type)
			return nil if sample_type.samples.length == 0

			prev_sample_type = sample_type.samples[0]&.linked_samples[0]&.sample_type
			return nil if prev_sample_type.blank?

			if detect_source(prev_sample_type)
				'source'
			elsif detect_sample(prev_sample_type)
				'sample'
			elsif detect_other_material(prev_sample_type)
				'other_material'
			elsif detect_data_file(prev_sample_type)
				'data_file'
			end
		end
	end
end

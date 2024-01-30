require 'test_helper'

class IsaAssaysControllerTest < ActionController::TestCase
  fixtures :all

  include AuthenticatedTestHelper
  include SharingFormTestHelper

  def setup
    login_as FactoryBot.create :user
  end

  test 'should get new' do
    inv = FactoryBot.create(:investigation, projects:, contributor: User.current_user.person)
    study = FactoryBot.create(:study, investigation_id: inv.id, contributor: User.current_user.person)
    sample_type = FactoryBot.create(:simple_sample_type)
    study.sample_types << sample_type

    get :new, params: { study_id: study }
    assert_response :success
    assert_not_nil assigns(:isa_assay)
  end

  test 'should create' do
    projects = User.current_user.person.projects
    inv = FactoryBot.create(:investigation, projects:, contributor: User.current_user.person)
    study = FactoryBot.create(:study, investigation_id: inv.id, contributor: User.current_user.person)
    other_creator = FactoryBot.create(:person)
    this_person = User.current_user.person

    source_sample_type = FactoryBot.create(:simple_sample_type, title: 'source sample_type')

    sample_collection_sample_type = FactoryBot.create(:multi_linked_sample_type, project_ids: [projects.first.id],
                                                                                 title: 'sample_collection sample_type')
    sample_collection_sample_type.sample_attributes.last.linked_sample_type = source_sample_type

    study.sample_types = [source_sample_type, sample_collection_sample_type]

    policy_attributes = { access_type: Policy::ACCESSIBLE,
                          permissions_attributes: project_permissions([projects.first], Policy::ACCESSIBLE) }

    assert_difference('Assay.count', 1) do
      assert_difference('SampleType.count', 1) do
        post :create, params: { isa_assay: { assay: { title: 'test', study_id: study.id,
                                                      sop_ids: [FactoryBot.create(:sop, policy: FactoryBot.create(:public_policy)).id],
                                                      creator_ids: [this_person.id, other_creator.id],
                                                      other_creators: 'other collaborators',
                                                      assay_class_id: AssayClass.experimental.id,
                                                      position: 0, policy_attributes: },
                                             input_sample_type_id: sample_collection_sample_type.id,
                                             sample_type: { title: 'assay sample_type', project_ids: [projects.first.id], template_id: 1,
                                                            sample_attributes_attributes: {
                                                              '0' => {
                                                                pos: '1', title: 'a string', required: '1', is_title: '1',
                                                                sample_attribute_type_id: FactoryBot.create(:string_sample_attribute_type).id, _destroy: '0',
                                                                isa_tag_id: FactoryBot.create(:other_material_isa_tag).id
                                                              },
                                                              '1' => {
                                                                pos: '2', title: 'protocol', required: '1', is_title: '0',
                                                                sample_attribute_type_id: FactoryBot.create(:string_sample_attribute_type).id,
                                                                isa_tag_id: FactoryBot.create(:protocol_isa_tag).id, _destroy: '0'
                                                              },
                                                              '2' => {
                                                                pos: '3', title: 'Input', required: '1',
                                                                sample_attribute_type_id: FactoryBot.create(:sample_multi_sample_attribute_type).id,
                                                                linked_sample_type_id: 'self', _destroy: '0'
                                                              },
                                                              '3' => {
                                                                pos: '4', title: 'Some material characteristic', required: '1',
                                                                sample_attribute_type_id: FactoryBot.create(:string_sample_attribute_type).id,
                                                                _destroy: '0',
                                                                isa_tag_id: FactoryBot.create(:other_material_characteristic_isa_tag).id
                                                              }
                                                            } } } }
      end
    end
    isa_assay = assigns(:isa_assay)
    assert_redirected_to controller: 'single_pages', action: 'show', id: isa_assay.assay.projects.first.id,
                         params: { notice: 'The ISA assay was created successfully!',
                                   item_type: 'assay', item_id: Assay.last.id }

    sample_types = SampleType.last(2)
    title = sample_types[0].sample_attributes.detect(&:is_title).title
    sample_multi = sample_types[1].sample_attributes.detect(&:seek_sample_multi?)

    assert_equal "Input (#{title})", sample_multi.title

    assert_equal [this_person, other_creator], isa_assay.assay.creators
    assert_equal 'other collaborators', isa_assay.assay.other_creators
  end

  test 'author form partial uses correct nested param attributes' do
    get :new, params: { study_id: FactoryBot.create(:study, contributor: User.current_user.person) }
    assert_response :success
    assert_select '#author-list[data-field-name=?]', 'isa_assay[assay][assets_creators_attributes]'
    assert_select '#isa_assay_assay_other_creators'
  end

  test 'should show new when parameters are incomplete' do
    projects = User.current_user.person.projects
    inv = FactoryBot.create(:investigation, projects:, contributor: User.current_user.person)
    study = FactoryBot.create(:study, investigation_id: inv.id, contributor: User.current_user.person)

    source_sample_type = FactoryBot.create(:simple_sample_type)

    sample_collection_sample_type = FactoryBot.create(:multi_linked_sample_type, project_ids: [projects.first.id])
    sample_collection_sample_type.sample_attributes.last.linked_sample_type = source_sample_type

    study.sample_types = [source_sample_type, sample_collection_sample_type]

    post :create, params: { isa_assay: {
      assay: { title: 'test', study_id: study.id,
               sop_ids: [FactoryBot.create(:sop, policy: FactoryBot.create(:public_policy)).id] },
      sample_type: {
        title: 'source', project_ids: [projects.first.id],
        sample_attributes_attributes: {}
      }
    } }

    assert_template :new
  end

  test 'should update isa assay' do
    person = User.current_user.person
    project = person.projects.first
    investigation = FactoryBot.create(:investigation, projects: [project])
    other_creator = FactoryBot.create(:person)

    source_type = FactoryBot.create(:isa_source_sample_type, contributor: person, projects: [project])
    sample_collection_type = FactoryBot.create(:isa_sample_collection_sample_type, contributor: person, projects: [project],
                                                                                   linked_sample_type: source_type)
    assay_type = FactoryBot.create(:isa_assay_material_sample_type, contributor: person, projects: [project],
                                                           linked_sample_type: sample_collection_type)

    study = FactoryBot.create(:study, investigation:, contributor: person,
                                      sops: [FactoryBot.create(:sop, policy: FactoryBot.create(:public_policy))],
                                      sample_types: [source_type, sample_collection_type])

    assay = FactoryBot.create(:assay, study:, contributor: person)
    put :update, params: { id: assay, isa_assay: { assay: { title: 'assay title' } } }
    assert_redirected_to single_page_path(id: project, item_type: 'assay', item_id: assay.id)
    assert flash[:error].include?('Resource not found.')

    assay = FactoryBot.create(:assay, study:, sample_type: assay_type, contributor: person)

    put :update, params: { id: assay, isa_assay: { assay: { title: 'assay title', sop_ids: [FactoryBot.create(:sop, policy: FactoryBot.create(:public_policy)).id],
                                                            creator_ids: [person.id, other_creator.id], other_creators: 'other collaborators' },
                                                   sample_type: { title: 'sample type title' } } }

    isa_assay = assigns(:isa_assay)
    assert_equal 'assay title', isa_assay.assay.title
    assert_equal 'sample type title', isa_assay.sample_type.title
    assert_redirected_to single_page_path(id: project, item_type: 'assay', item_id: assay.id)

    assert_equal [person, other_creator], isa_assay.assay.creators
    assert_equal 'other collaborators', isa_assay.assay.other_creators
  end

  test 'should create an isa assay with extended metadata' do
    projects = User.current_user.person.projects
    inv = FactoryBot.create(:investigation, projects:, contributor: User.current_user.person)
    study = FactoryBot.create(:study, investigation_id: inv.id, contributor: User.current_user.person)
    other_creator = FactoryBot.create(:person)
    this_person = User.current_user.person

    source_sample_type = FactoryBot.create(:simple_sample_type, title: 'source sample_type')

    sample_collection_sample_type = FactoryBot.create(:multi_linked_sample_type, project_ids: [projects.first.id],
                                                                                 title: 'sample_collection sample_type')
    sample_collection_sample_type.sample_attributes.last.linked_sample_type = source_sample_type

    study.sample_types = [source_sample_type, sample_collection_sample_type]

    policy_attributes = { access_type: Policy::ACCESSIBLE,
                          permissions_attributes: project_permissions([projects.first], Policy::ACCESSIBLE) }

    emt = FactoryBot.create(:simple_assay_extended_metadata_type)

    emt_attributes = { extended_metadata_attributes: {
      extended_metadata_type_id: emt.id,
      data: {
        "age": 43,
        "name": 'Jane Doe',
        "date": '14-11-1980'
      }
    } }

    assay_attributes = { title: 'First assay with custom metadata', study_id: study.id,
                         sop_ids: [FactoryBot.create(:sop, policy: FactoryBot.create(:public_policy)).id],
                         creator_ids: [this_person.id, other_creator.id],
                         other_creators: 'other collaborators',
                         position: 0, assay_class_id: AssayClass.experimental.id, policy_attributes: }

    isa_assay_attributes = { assay: assay_attributes.merge(emt_attributes),
                             input_sample_type_id: sample_collection_sample_type.id,
                             sample_type: { title: 'assay sample_type', project_ids: [projects.first.id], template_id: 1,
                                            sample_attributes_attributes: {
                                              '0' => {
                                                pos: '1', title: 'a string', required: '1', is_title: '1',
                                                sample_attribute_type_id: FactoryBot.create(:string_sample_attribute_type).id, _destroy: '0',
                                                isa_tag_id: FactoryBot.create(:other_material_isa_tag).id
                                              },
                                              '1' => {
                                                pos: '2', title: 'protocol', required: '1', is_title: '0',
                                                sample_attribute_type_id: FactoryBot.create(:string_sample_attribute_type).id,
                                                isa_tag_id: FactoryBot.create(:protocol_isa_tag).id, _destroy: '0'
                                              },
                                              '2' => {
                                                pos: '3', title: 'Input', required: '1',
                                                sample_attribute_type_id: FactoryBot.create(:sample_multi_sample_attribute_type).id,
                                                linked_sample_type_id: 'self', _destroy: '0'
                                              },
                                              '3' => {
                                                pos: '4', title: 'Some material characteristic', required: '1',
                                                sample_attribute_type_id: FactoryBot.create(:string_sample_attribute_type).id,
                                                _destroy: '0',
                                                isa_tag_id: FactoryBot.create(:other_material_characteristic_isa_tag).id
                                              }
                                            } } }

    assert_difference 'Assay.count', 1 do
      assert_difference 'ExtendedMetadata.count', 1 do
        post :create,
             params: { isa_assay: isa_assay_attributes }
      end
    end
  end

  test 'hide sops, publications, documents, and discussion channels if assay stream' do
    person = FactoryBot.create(:person)
    study = FactoryBot.create(:isa_json_compliant_study, contributor: person)
    assay_stream = FactoryBot.create(:assay_stream, study: , contributor: person)

    get :new, params: {study_id: study.id, is_assay_stream: true}
    assert_response :success

    assert_select 'div#add_sops_form', text: /SOPs/i, count: 0
    assert_select 'div#add_publications_form', text: /Publications/i, count: 0
    assert_select 'div#add_documents_form', text: /Documents/i, count: 0
    assert_select 'div.panel-heading', text: /Discussion Channels/i, count: 0
    assert_select 'div.panel-heading', text: /Define Sample type for Assay/i, count: 0

    get :edit, params: { id: assay_stream.id, study_id: study.id, source_assay_id: assay_stream.id, is_assay_stream: true }
    assert_response :success

    assert_select 'div#add_sops_form', text: /SOPs/i, count: 0
    assert_select 'div#add_publications_form', text: /Publications/i, count: 0
    assert_select 'div#add_documents_form', text: /Documents/i, count: 0
    assert_select 'div.panel-heading', text: /Discussion Channels/i, count: 0
    assert_select 'div.panel-heading', text: /Define Sample type for Assay/i, count: 0
  end

  test 'show sops, publications, documents, and discussion channels if experimental assay' do
    person = FactoryBot.create(:person)
    project = person.projects.first
    investigation = FactoryBot.create(:investigation, is_isa_json_compliant: true, contributor: person, projects: [project])
    study = FactoryBot.create(:isa_json_compliant_study, contributor: person, investigation: )
    assay_stream = FactoryBot.create(:assay_stream, study: , contributor: person, position: 0)

    login_as(person)

    get :new, params: {study_id: study.id, assay_stream_id: assay_stream.id, source_assay_id: assay_stream.id}
    assert_response :success

    assert_select 'div#add_sops_form', text: /SOPs/i, count: 1
    assert_select 'div#add_publications_form', text: /Publications/i, count: 1
    assert_select 'div#add_documents_form', text: /Documents/i, count:1
    assert_select 'div.panel-heading', text: /Discussion Channels/i, count: 1
    assert_select 'div.panel-heading', text: /Define Sample type for Assay/i, count: 1

    first_assay_st = FactoryBot.create(:isa_assay_material_sample_type, contributor: person, projects: [project], linked_sample_type: study.sample_types.second)
    first_assay = FactoryBot.create(:assay, contributor: person, study: , assay_stream: , position: 1, sample_type: first_assay_st)
    assert_equal assay_stream, first_assay.assay_stream

    get :edit, params: { id: first_assay.id, assay_stream_id: assay_stream.id, source_assay_id: first_assay.id, study_id: study.id }
    assert_response :success

    assert_select 'div#add_sops_form', text: /SOPs/i, count: 1
    assert_select 'div#add_publications_form', text: /Publications/i, count: 1
    assert_select 'div#add_documents_form', text: /Documents/i, count: 1
    assert_select 'div.panel-heading', text: /Discussion Channels/i, count: 1
    assert_select 'div.panel-heading', text: /Define Sample type for Assay/i, count: 1
  end

  test 'insert assay between assay stream and experimental assay' do
    # TODO: Test button text
    person = FactoryBot.create(:person)
    project = person.projects.first
    login_as(person)
    investigation = FactoryBot.create(:investigation, is_isa_json_compliant: true, contributor: person)
    study = FactoryBot.create(:isa_json_compliant_study, investigation: , contributor: person )

    ## Create an assay stream
    assay_stream = FactoryBot.create(:assay_stream, contributor: person, study: )
    assert assay_stream.is_assay_stream?
    assert_equal assay_stream.previous_linked_sample_type, study.sample_types.second
    assert_nil assay_stream.next_linked_child_assay

    ## Create an assay at the end of the stream
    end_assay_sample_type = FactoryBot.create(:isa_assay_material_sample_type,
    linked_sample_type: study.sample_types.second,
    projects: [project],
    contributor: person)
    end_assay = FactoryBot.create(:assay, contributor: person, study: , sample_type: end_assay_sample_type, assay_stream: )

    refute end_assay.is_assay_stream?
    assert_equal end_assay.previous_linked_sample_type, assay_stream.previous_linked_sample_type, study.sample_types.second
    assert_nil end_assay.next_linked_child_assay

    # Test assay linkage
    ## Post intermediate assay
    policy_attributes = { access_type: Policy::ACCESSIBLE,
                          permissions_attributes: project_permissions([projects.first], Policy::ACCESSIBLE) }

    intermediate_assay_attributes1 = { title: 'First intermediate assay',
                                      study_id: study.id,
                                      assay_class_id: AssayClass.for_type(Seek:: ISA:: AssayClass::EXP).id,
                                      creator_ids: [person.id],
                                      policy_attributes: ,
                                      assay_stream_id: assay_stream.id}

    intermediate_assay_sample_type_attributes1 = { title: "Intermediate Assay Sample type 1",
                                                    project_ids: [project.id],
                                                    sample_attributes_attributes: {
                                                      '0': {
                                                        pos: '1', title: 'a string', required: '1', is_title: '1',
                                                        sample_attribute_type_id: FactoryBot.create(:string_sample_attribute_type).id, _destroy: '0',
                                                        isa_tag_id: FactoryBot.create(:other_material_isa_tag).id
                                                      },
                                                      '1': {
                                                        pos: '2', title: 'protocol', required: '1', is_title: '0',
                                                        sample_attribute_type_id: FactoryBot.create(:string_sample_attribute_type).id,
                                                        isa_tag_id: FactoryBot.create(:protocol_isa_tag).id, _destroy: '0'
                                                      },
                                                      '2': {
                                                        pos: '3', title: 'Input sample', required: '1',
                                                        sample_attribute_type_id: FactoryBot.create(:sample_multi_sample_attribute_type).id,
                                                        linked_sample_type_id: study.sample_types.second.id, _destroy: '0'
                                                      },
                                                      '3': {
                                                        pos: '4', title: 'Some material characteristic', required: '1',
                                                        sample_attribute_type_id: FactoryBot.create(:string_sample_attribute_type).id,
                                                        _destroy: '0',
                                                        isa_tag_id: FactoryBot.create(:other_material_characteristic_isa_tag).id
                                                      }
                                                    }
                                                  }

    intermediate_isa_assay_attributes1 = { assay: intermediate_assay_attributes1,
                                           input_sample_type_id: study.sample_types.second.id,
                                           sample_type: intermediate_assay_sample_type_attributes1 }

    assert_difference "Assay.count", 1 do
      assert_difference "SampleType.count", 1 do
        post :create, params: { isa_assay: intermediate_isa_assay_attributes1 }
      end
    end

    isa_assay = assigns(:isa_assay)
    assert_redirected_to single_page_path(id: project, item_type: 'assay', item_id: isa_assay.assay.id, notice: 'The ISA assay was created successfully!')

    assert_equal isa_assay.assay.sample_type.previous_linked_sample_type, study.sample_types.second
    assert_equal isa_assay.assay.next_linked_child_assay, end_assay
  end

  test 'insert assay between two experimental assays' do
    # TODO: Test button text
    person = FactoryBot.create(:person)
    project = person.projects.first
    login_as(person)
    investigation = FactoryBot.create(:investigation, is_isa_json_compliant: true, contributor: person)
    study = FactoryBot.create(:isa_json_compliant_study, investigation: , contributor: person )

    ## Create an assay stream
    assay_stream = FactoryBot.create(:assay_stream, contributor: person, study: )
    assert assay_stream.is_assay_stream?
    assert_equal assay_stream.previous_linked_sample_type, study.sample_types.second
    assert_nil assay_stream.next_linked_child_assay

    ## Create an assay at the begin of the stream
    begin_assay_sample_type = FactoryBot.create(:isa_assay_material_sample_type,
                                                linked_sample_type: study.sample_types.second,
                                                projects: [project],
                                                contributor: person)
    begin_assay = FactoryBot.create(:assay, title: 'Begin Assay', contributor: person, study: , sample_type: begin_assay_sample_type, assay_stream: )

    ## Create an assay at the end of the stream
    end_assay_sample_type = FactoryBot.create(:isa_assay_data_file_sample_type,
                                              linked_sample_type: begin_assay_sample_type,
                                              projects: [project],
                                              contributor: person)
    end_assay = FactoryBot.create(:assay, title: 'End Assay', contributor: person, study: , sample_type: end_assay_sample_type, assay_stream: )

    refute end_assay.is_assay_stream?
    assert_equal begin_assay.previous_linked_sample_type, assay_stream.previous_linked_sample_type, study.sample_types.second
    assert_nil end_assay.next_linked_child_assay

    # Test assay linkage
    ## Post intermediate assay
    policy_attributes = { access_type: Policy::ACCESSIBLE,
                          permissions_attributes: project_permissions([projects.first], Policy::ACCESSIBLE) }

    intermediate_assay_attributes2 = { title: 'Second intermediate assay',
                                      study_id: study.id,
                                      assay_class_id: AssayClass.for_type(Seek:: ISA:: AssayClass::EXP).id,
                                      creator_ids: [person.id],
                                      policy_attributes: ,
                                      assay_stream_id: assay_stream.id}

    intermediate_assay_sample_type_attributes2 = { title: "Intermediate Assay Sample type 2",
                                                    project_ids: [project.id],
                                                    sample_attributes_attributes: {
                                                      '0': {
                                                        pos: '1', title: 'a string', required: '1', is_title: '1',
                                                        sample_attribute_type_id: FactoryBot.create(:string_sample_attribute_type).id, _destroy: '0',
                                                        isa_tag_id: FactoryBot.create(:other_material_isa_tag).id
                                                      },
                                                      '1': {
                                                        pos: '2', title: 'protocol', required: '1', is_title: '0',
                                                        sample_attribute_type_id: FactoryBot.create(:string_sample_attribute_type).id,
                                                        isa_tag_id: FactoryBot.create(:protocol_isa_tag).id, _destroy: '0'
                                                      },
                                                      '2': {
                                                        pos: '3', title: 'Input sample', required: '1',
                                                        sample_attribute_type_id: FactoryBot.create(:sample_multi_sample_attribute_type).id,
                                                        linked_sample_type_id: study.sample_types.second.id, _destroy: '0'
                                                      },
                                                      '3': {
                                                        pos: '4', title: 'Some material characteristic', required: '1',
                                                        sample_attribute_type_id: FactoryBot.create(:string_sample_attribute_type).id,
                                                        _destroy: '0',
                                                        isa_tag_id: FactoryBot.create(:other_material_characteristic_isa_tag).id
                                                      }
                                                    }
                                                  }

    intermediate_isa_assay_attributes2 = { assay: intermediate_assay_attributes2,
                                           input_sample_type_id: begin_assay_sample_type.id,
                                           sample_type: intermediate_assay_sample_type_attributes2 }


    assert_difference "Assay.count", 1 do
      assert_difference "SampleType.count", 1 do
        post :create, params: { isa_assay: intermediate_isa_assay_attributes2 }
      end
    end

    isa_assay = assigns(:isa_assay)
    assert_redirected_to single_page_path(id: project, item_type: 'assay', item_id: isa_assay.assay.id, notice: 'The ISA assay was created successfully!')

    puts "Assay added: #{isa_assay.assay.inspect}"
    puts "Assay ST added: #{isa_assay.assay.sample_type.inspect}"
    puts "Assay from DB added: #{Assay.last.inspect}"

    assert_equal begin_assay.previous_linked_sample_type, study.sample_types.second
    assert_equal isa_assay.assay.sample_type.previous_linked_sample_type, begin_assay.sample_type
    assert_equal isa_assay.assay.next_linked_child_assay, end_assay
  end

end

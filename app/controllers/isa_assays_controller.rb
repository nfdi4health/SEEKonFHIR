class IsaAssaysController < ApplicationController
  include Seek::AssetsCommon
  include Seek::Publishing::PublishingCommon

  before_action :set_up_instance_variable
  before_action :find_requested_item, only: %i[edit update]
  after_action :fix_assay_linkage_for_new_assays, only: :create

  def new
    if params[:is_assay_stream]
      @isa_assay = IsaAssay.new({ assay: { assay_class_id: AssayClass.assay_stream.id } })
    else
      @isa_assay = IsaAssay.new({ assay: { assay_class_id: AssayClass.experimental.id } })
    end
  end

  def create
    @isa_assay = IsaAssay.new(isa_assay_params)
    update_sharing_policies @isa_assay.assay
    @isa_assay.assay.contributor = current_person
    @isa_assay.sample_type.contributor = User.current_user.person if isa_assay_params[:sample_type]
    if @isa_assay.save
      redirect_to single_page_path(id: @isa_assay.assay.projects.first, item_type: 'assay',
                                   item_id: @isa_assay.assay, notice: 'The ISA assay was created successfully!')
    else
      respond_to do |format|
        format.html { render action: 'new' }
        format.json { render json: json_api_errors(@isa_assay), status: :unprocessable_entity }
      end
    end
  end

  def edit
    # let edit the assay if the sample_type is not authorized
    if @isa_assay.assay.is_assay_stream?
      @isa_assay.sample_type = nil
    else
      @isa_assay.sample_type = nil unless requested_item_authorized?(@isa_assay.sample_type)
    end

    respond_to do |format|
      format.html
    end
  end

  def update
    @isa_assay.assay.attributes = isa_assay_params[:assay]

    # update the sample_type
    unless @isa_assay.assay.is_assay_stream?
      if requested_item_authorized?(@isa_assay.sample_type)
        @isa_assay.sample_type.update(isa_assay_params[:sample_type])
        @isa_assay.sample_type.resolve_inconsistencies
      end
    end

    if @isa_assay.save
      redirect_to single_page_path(id: @isa_assay.assay.projects.first, item_type: 'assay',
                                   item_id: @isa_assay.assay.id)
    else
      respond_to do |format|
        format.html { render action: 'edit', status: :unprocessable_entity }
        format.json { render json: @isa_assay.errors, status: :unprocessable_entity }
      end
    end
  end

  def fix_assay_linkage_for_new_assays
    return unless @isa_assay.assay.is_isa_json_compliant?

    previous_assay_st = @isa_assay.assay.previous_linked_sample_type
    previous_assay = previous_assay_st.assays.first
    next_assay = previous_assay.next_linked_child_assay
    next_assay.update(position: @isa_assay.assay.position + 1)
    return unless next_assay

    current_assay_st = @isa_assay.assay.sample_type
    previous_assay_st.update(linked_sample_attribute_ids: [@isa_assay.assay.sample_type.sample_attributes.detect { |sa| sa.isa_tag.nil? && sa.title.include?('Input') }.id])
    current_assay_st.update(linked_sample_attribute_ids: [next_assay.sample_type.sample_attributes.detect { |sa| sa.isa_tag.nil? && sa.title.include?('Input') }.id])
  end

  private

  def isa_assay_params
    # TODO: get the params from a shared module
    isa_assay_params = params.require(:isa_assay).permit(
      { assay: assay_params, sample_type: sample_type_params(params[:isa_assay]) }, :input_sample_type_id
    )
    if isa_assay_params.key?(:document_ids)
      params[:isa_assay][:assay][:document_ids].select! do |id|
        Document.find_by_id(id).try(:can_view?)
      end
    end
    if isa_assay_params.key?(:sop_ids)
      params[:isa_assay][:assay][:sop_ids].select! do |id|
        Sop.find_by_id(id).try(:can_view?)
      end
    end
    if isa_assay_params.key?(:model_ids)
      params[:isa_assay][:assay][:model_ids].select! do |id|
        Model.find_by_id(id).try(:can_view?)
      end
    end
    isa_assay_params
  end

  def assay_params
    [:title, :description, :study_id, :assay_class_id, :assay_type_uri, :technology_type_uri,
     :license, *creator_related_params, :position, { document_ids: [] },
     { scales: [] }, { sop_ids: [] }, { model_ids: [] },
     { samples_attributes: %i[asset_id direction] },
     { data_files_attributes: %i[asset_id direction relationship_type_id] },
     { publication_ids: [] },
     { extended_metadata_attributes: determine_extended_metadata_keys(:assay) },
     { discussion_links_attributes: %i[id url label _destroy] }, :assay_stream_id]
  end

  def sample_type_params(params)
    return [] unless params[:sample_type]

    attributes = params[:sample_type][:sample_attributes]
    if attributes
      params[:sample_type][:sample_attributes_attributes] = []
      attributes.each do |attribute|
        if attribute[:sample_attribute_type]
          if attribute[:sample_attribute_type][:id]
            attribute[:sample_attribute_type_id] = attribute[:sample_attribute_type][:id].to_i
          elsif attribute[:sample_attribute_type][:title]
            attribute[:sample_attribute_type_id] =
              SampleAttributeType.where(title: attribute[:sample_attribute_type][:title]).first.id
          end
        end
        attribute[:unit_id] = Unit.where(symbol: attribute[:unit_symbol]).first.id unless attribute[:unit_symbol].nil?
        params[:sample_type][:sample_attributes_attributes] << attribute
      end
    end

    if params[:sample_type][:assay_assets_attributes]
      params[:sample_type][:assay_ids] = params[:sample_type][:assay_assets_attributes].map { |x| x[:assay_id] }
    end

    [:title, :description, :tags, :template_id,
     { project_ids: [],
       sample_attributes_attributes: %i[id title pos required is_title
                                        sample_attribute_type_id isa_tag_id
                                        sample_controlled_vocab_id
                                        linked_sample_type_id
                                        description pid
                                        allow_cv_free_text
                                        unit_id _destroy] }, { assay_ids: [] }]
  end

  def set_up_instance_variable
    @single_page = true
  end

  def find_requested_item
    if params[:is_assay_stream]
      @isa_assay = IsaAssay.new({ assay: { assay_class_id: AssayClass.assay_stream.id } })
    else
      @isa_assay = IsaAssay.new({ assay: { assay_class_id: AssayClass.experimental.id } })
    end
    @isa_assay.populate(params[:id])

    # Should not deal with sample type if assay has assay_class assay stream
    return if @isa_assay.assay.is_assay_stream?

    if @isa_assay.sample_type.nil? || !requested_item_authorized?(@isa_assay.assay)
      flash[:error] = "You are not authorized to edit this #{t('isa_assay')}"
      flash[:error] = 'Resource not found.' if @isa_assay.sample_type.nil?

      redirect_to single_page_path(id: @isa_assay.assay.projects.first, item_type: 'assay',
                                   item_id: @isa_assay.assay)
    end
  end
end

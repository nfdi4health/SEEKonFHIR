class IsaAssay
  include ActiveModel::Model

  attr_accessor :assay, :sample_type, :input_sample_type_id

  validates_presence_of :assay, :sample_type, :input_sample_type_id
  validate :validate_objects

  def initialize(params = {})
    @assay = Assay.new(params[:assay] || {})
    @sample_type = SampleType.new((params[:sample_type] || {}).merge({ project_ids: @assay.project_ids }))
    @sample_type.sample_attributes.build(is_title: true, required: true) unless params[:sample_type]
    @assay.sample_type = @sample_type
    @assay.assay_class = AssayClass.for_type('experimental')
    @input_sample_type_id = params[:input_sample_type_id]
  end

  def save
    if valid?
      # connect the sample type multi link attribute to the last sample type of the assay's study
      input_attribute = @sample_type.sample_attributes.detect(&:seek_sample_multi?)
      input_attribute.linked_sample_type_id = @input_sample_type_id
      title = SampleType.find(@input_sample_type_id).sample_attributes.detect(&:is_title).title 
			input_attribute.title = "Input (#{title})"

      @assay.save
      @sample_type.save
    else
      false
    end
  end

  attr_reader :assay, :sample_type

  def can_manage?(user = User.current_user)
    user && user.person == @assay.contributor
  end

  def isa_object
    @assay
  end

  private

  def validate_objects
    @assay.errors.each { |e| errors[:base] << "[Assay]: #{e}" } unless @assay.valid?
    errors[:base] << 'SOP is required' if @assay.sop_ids.blank?

    @sample_type.errors.full_messages.each { |e| errors[:base] << "[Sample type]: #{e}" } unless @sample_type.valid?

    unless @sample_type.sample_attributes.any?(&:seek_sample_multi?)
      errors[:base] << '[Sample type]: SEEK Sample Multi attribute is not provided'
    end

    unless @sample_type.sample_attributes.select { |a| a.isa_tag&.isa_protocol? }.one?
      errors[:base] << '[Sample type]: An attribute with Protocol ISA tag is not provided'
    end

    errors[:base] << '[Input Assay]: Input Assay is not provided' if @input_sample_type_id.blank?
  end
end

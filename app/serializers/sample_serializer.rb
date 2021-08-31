class SampleSerializer < ContributedResourceSerializer

  attribute :attribute_map do
    object.data.to_hash
  end

  has_one :sample_type
  has_many :projects
  has_many :data_files
  has_many :people

end
 

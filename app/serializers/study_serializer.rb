class StudySerializer < SnapshottableSerializer
  attributes :title, :description, :experimentalists, :other_creators , :position

  has_many :people
  has_many :projects
  has_one :investigation
  has_many :assays
  has_many :data_files
  has_many :models
  has_many :sops
  has_many :publications
  has_many :documents

  attribute :creators do
    serialize_assets_creators
  end
end

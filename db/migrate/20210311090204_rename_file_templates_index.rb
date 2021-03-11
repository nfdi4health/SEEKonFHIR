class RenameFileTemplatesIndex < ActiveRecord::Migration[5.2]
  def change
    rename_index :file_template_versions_projects, 'index_file_template_versions_projects_on_project_id', 'index_ft_versions_projects_on_project_id'
    rename_index :file_template_versions_projects, 'index_ft_versions_projects_on_version_id_and_project_id', 'index_ft_versions_projects_on_v_id_and_p_id'
    rename_index :file_template_versions_projects, 'index_file_template_versions_projects_on_version_id', 'index_ft_versions_projects_on_version_id'
  end
end

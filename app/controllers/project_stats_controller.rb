class ProjectStatsController < StatsController
  private

  def stats
    Seek::Stats::ProjectDashboardStats.new(@project)
  end

  def get_scope
    name = t('project')
    @scope = @project = Project.find_by_id(params[:project_id])
    if @project.nil?
      respond_to do |format|
        flash[:error] = "The #{name.humanize} does not exist!"
        format.html { redirect_to project_path(@project) }
      end
    end
  end

  def check_access_rights
    unless @project.has_member?(current_user)
      flash[:error] = "You are not a member of this #{t('project')}, so cannot access this page."
      redirect_to project_path(@project)
      false
    end
  end
end

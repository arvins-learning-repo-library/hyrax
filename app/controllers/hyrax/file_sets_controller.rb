module Hyrax
  class FileSetsController < ApplicationController
    rescue_from WorkflowAuthorizationException, with: :render_unavailable

    include Blacklight::Base
    include Blacklight::AccessControls::Catalog
    include Hyrax::Breadcrumbs

    before_action :authenticate_user!, except: [:show, :citation, :stats]
    load_and_authorize_resource class: ::FileSet, except: :show
    before_action :build_breadcrumbs, only: [:show, :edit, :stats]

    # provides the help_text view method
    helper PermissionsHelper

    helper_method :curation_concern
    copy_blacklight_config_from(::CatalogController)

    class_attribute :show_presenter, :form_class
    self.show_presenter = Hyrax::FileSetPresenter
    self.form_class = Hyrax::Forms::FileSetEditForm

    # A little bit of explanation, CanCan(Can) sets the @file_set via the .load_and_authorize_resource
    # method. However the interface for various CurationConcern modules leverages the #curation_concern method
    # Thus we have file_set and curation_concern that are aliases for each other.
    attr_accessor :file_set
    alias curation_concern file_set
    private :file_set=
    alias curation_concern= file_set=
    private :curation_concern=
    helper_method :file_set

    layout :decide_layout

    # GET /concern/file_sets/:id
    def edit
      initialize_edit_form
    end

    # GET /concern/parent/:parent_id/file_sets/:id
    def show
      workflow_check(parent_id: params[:parent_id])
      respond_to do |wants|
        wants.html { presenter }
        wants.json { presenter }
        additional_response_formats(wants)
      end
    end

    # DELETE /concern/file_sets/:id
    def destroy
      parent = curation_concern.parent
      workflow_check(parent_id: parent.id)
      actor.destroy
      redirect_to [main_app, parent], notice: view_context.t('hyrax.file_sets.asset_deleted_flash.message')
    end

    # PATCH /concern/file_sets/:id
    def update
      parent = curation_concern.parent
      workflow_check(parent_id: parent.id)
      if attempt_update
        after_update_response
      else
        after_update_failure_response
      end
    rescue RSolr::Error::Http => error
      flash[:error] = error.message
      logger.error "FileSetsController::update rescued #{error.class}\n\t#{error.message}\n #{error.backtrace.join("\n")}\n\n"
      render action: 'edit'
    end

    # GET /files/:id/stats
    def stats
      @stats = FileUsage.new(params[:id])
    end

    # GET /files/:id/citation
    def citation; end

    private

      # this is provided so that implementing application can override this behavior and map params to different attributes
      def update_metadata
        file_attributes = form_class.model_attributes(attributes)
        actor.update_metadata(file_attributes)
      end

      def attempt_update
        if wants_to_revert?
          actor.revert_content(params[:revision])
        elsif params.key?(:file_set)
          if params[:file_set].key?(:files)
            actor.update_content(params[:file_set][:files].first)
          else
            update_metadata
          end
        end
      end

      def after_update_response
        respond_to do |wants|
          wants.html do
            link_to_file = view_context.link_to(curation_concern, [main_app, curation_concern])
            redirect_to [main_app, curation_concern], notice: view_context.t('hyrax.file_sets.asset_updated_flash.message', link_to_file: link_to_file)
          end
          wants.json do
            @presenter = show_presenter.new(curation_concern, current_ability)
            render :show, status: :ok, location: polymorphic_path([main_app, curation_concern])
          end
        end
      end

      def after_update_failure_response
        respond_to do |wants|
          wants.html do
            initialize_edit_form
            flash[:error] = "There was a problem processing your request."
            render 'edit', status: :unprocessable_entity
          end
          wants.json { render_json_response(response_type: :unprocessable_entity, options: { errors: curation_concern.errors }) }
        end
      end

      def add_breadcrumb_for_controller
        add_breadcrumb I18n.t('hyrax.dashboard.my.works'), hyrax.my_works_path
      end

      def add_breadcrumb_for_action
        case action_name
        when 'edit'.freeze
          add_breadcrumb I18n.t("hyrax.file_set.browse_view"), main_app.hyrax_file_set_path(params["id"])
        when 'show'.freeze
          add_breadcrumb presenter.parent.to_s, main_app.polymorphic_path(presenter.parent)
          add_breadcrumb presenter.to_s, main_app.polymorphic_path(presenter)
        end
      end

      # Override of Blacklight::RequestBuilders
      def search_builder_class
        Hyrax::FileSetSearchBuilder
      end

      def initialize_edit_form
        @parent = @file_set.in_objects.first
        workflow_check(parent_id: @parent.id)
        original = @file_set.original_file
        @version_list = Hyrax::VersionListPresenter.new(original ? original.versions.all : [])
        @groups = current_user.groups
      end

      def workflow_check(parent_id: nil)
        return if current_ability.can?(:edit, @solr_document)
        if parent_id.nil?
          curation_concern = ::FileSet.find(params[:id])
          parent = curation_concern.parent
          parent_id = parent.id
        end
        doc = ::SolrDocument.find(parent_id)
        return if current_ability.can?(:edit, doc)
        raise WorkflowAuthorizationException if doc.suppressed?
      end

      def actor
        @actor ||= Hyrax::Actors::FileSetActor.new(@file_set, current_user)
      end

      def attributes
        params.fetch(:file_set, {}).except(:files).permit!.dup # use a copy of the hash so that original params stays untouched when interpret_visibility modifies things
      end

      def presenter
        @presenter ||= begin
          _, document_list = search_results(params)
          curation_concern = document_list.first
          raise CanCan::AccessDenied unless curation_concern
          pres = show_presenter.new(curation_concern, current_ability, request)
          raise WorkflowAuthorizationException if pres.parent_presenter.blank?
          pres
        end
      end

      def wants_to_revert?
        params.key?(:revision) && params[:revision] != curation_concern.latest_content_version.label
      end

      # Override this method to add additional response formats to your local app
      def additional_response_formats(_); end

      # This allows us to use the unauthorized and form_permission template in hyrax/base,
      # while prefering our local paths. Thus we are unable to just override `self.local_prefixes`
      def _prefixes
        @_prefixes ||= super + ['hyrax/base']
      end

      def decide_layout
        layout = case action_name
                 when 'show'
                   '1_column'
                 else
                   'dashboard'
                 end
        File.join(theme, layout)
      end

      # rubocop:disable Metrics/MethodLength
      def render_unavailable
        message = I18n.t("hyrax.workflow.unauthorized_parent")
        respond_to do |wants|
          wants.html do
            unavailable_presenter
            flash[:notice] = message
            render 'unavailable', status: :unauthorized
          end
          wants.json do
            render plain: message, status: :unauthorized
          end
          additional_response_formats(wants)
          wants.ttl do
            render plain: message, status: :unauthorized
          end
          wants.jsonld do
            render plain: message, status: :unauthorized
          end
          wants.nt do
            render plain: message, status: :unauthorized
          end
        end
      end
      # rubocop:enable Metrics/MethodLength

      def unavailable_presenter
        @presenter ||= show_presenter.new(::SolrDocument.find(params[:id]), current_ability, request)
      end
  end
end

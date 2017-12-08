# This tests the Hyrax::WorksControllerBehavior module
# which is included into .internal_test_app/app/controllers/hyrax/generic_works_controller.rb
RSpec.describe Hyrax::GenericWorksController do
  routes { Rails.application.routes }

  let(:user) { create(:user) }

  before { sign_in user }

  context "JSON" do
    let(:resource) { create_for_repository(:work, :private, user: user) }
    let(:resource_request) { get :show, params: { id: resource, format: :json } }

    subject { response }

    describe "unauthorized" do
      before do
        sign_out user
        resource_request
      end
      it { is_expected.to respond_unauthorized }
    end

    describe "forbidden" do
      before do
        sign_in create(:user)
        resource_request
      end
      it { is_expected.to respond_forbidden }
    end

    describe 'created' do
      let(:actor) { double(create: model) }
      let(:model) { stub_model(GenericWork) }

      before do
        allow(Hyrax::CurationConcern).to receive(:actor).and_return(actor)
        post :create, params: { generic_work: { title: ['a title'] }, format: :json }
      end

      it "returns 201, renders show template sets location header" do
        # Ensure that @resource is set for jbuilder template to use
        expect(assigns[:resource]).to be_instance_of GenericWork
        expect(controller).to render_template('hyrax/base/show')
        expect(response.code).to eq "201"
        expect(response.location).to eq main_app.hyrax_generic_work_path(model, locale: 'en')
      end
    end

    # The clean is here because this test depends on the repo not having an AdminSet/PermissionTemplate created yet
    describe 'failed create', :clean_repo do
      before { post :create, params: { generic_work: {}, format: :json } }
      it "returns 422 and the errors" do
        change_set = assigns[:change_set]
        expect(response).to respond_unprocessable_entity(errors: change_set.errors.messages.as_json)
      end
    end

    describe 'found' do
      before { resource_request }
      it "returns json of the work" do
        # Ensure that @resource is set for jbuilder template to use
        expect(assigns[:resource]).to be_instance_of GenericWork
        expect(controller).to render_template('hyrax/base/show')
        expect(response.code).to eq "200"
      end
    end

    describe 'updated' do
      before { put :update, params: { id: resource, generic_work: { title: ['updated title'] }, format: :json } }
      it "returns 200, renders show template sets location header" do
        # Ensure that @resource is set for jbuilder template to use
        expect(assigns[:resource]).to be_instance_of GenericWork
        expect(controller).to render_template('hyrax/base/show')
        expect(response.code).to eq "200"
        created_resource = assigns[:resource]
        expect(response.location).to eq main_app.hyrax_generic_work_path(created_resource, locale: 'en')
      end
    end

    describe 'failed update' do
      before do
        post :update, params: { id: resource, generic_work: { title: [''] }, format: :json }
      end
      it "returns 422 and the errors" do
        expect(response).to respond_unprocessable_entity(errors: { title: ["Your Generic work must have a title."] })
      end
    end
  end
end

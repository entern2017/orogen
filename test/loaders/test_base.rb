require 'orogen/test'

describe OroGen::Loaders::Base do
    attr_reader :loader

    before do
        @loader = flexmock(OroGen::Loaders::Base.new)
    end

    describe "#project_model_from_name" do
        before do
            OroGen::Loaders::RTT.setup_loader(loader)
        end
        it "should build the model from text" do
            orogen_model =<<-EOMODEL
            name "test"
            task_context "Task" do
            end
            EOMODEL
            flexmock(loader).should_receive(:project_model_text_from_name).
                with('test').and_return([orogen_model, nil])

            model = loader.project_model_from_name('test')
            assert_equal 'test', model.name
            assert model.self_tasks['test::Task']
        end
    end

    describe "#project_model_from_text" do
        before do
            OroGen::Loaders::RTT.setup_loader(loader)

            @project = loader.project_model_from_text(<<-END)
            name 'test'
            task_context 'Task' do
            end
            END
        end

        it "validates the consistency between expected and actual name" do
            assert_raises(ArgumentError) do
                loader.project_model_from_text(<<-END, name: 'blo')
                name 'bla'
                END
            end
        end

        it "registers the project model after having parsed it" do
            assert_equal 'test', @project.name
            assert_same @project.find_task_context('test::Task'),
                loader.task_model_from_name('test::Task')
        end

        it "makes the project available to #project_model_from_name" do
            assert_same @project, loader.project_model_from_name('test')
        end

        it "registers the project as being available" do
            assert loader.has_project?('test')
        end
    end

    describe "#typekit_model_from_name" do
        attr_reader :typekit
        before do
            tlb =<<-EOF
<?xml version="1.0"?>
<typelib>
  <container name="/std/string" of="/int8_t" size="0" kind="/std/string" />
  <alias name="/string" source="/std/string"/>
</typelib>
            EOF
            typelist=<<-EOF
            /string 1
            EOF
            loader.should_receive(:typekit_model_text_from_name).
                with('test').and_return([tlb, typelist])

            @typekit = loader.typekit_model_from_name('test')
        end

        it "should register the type-to-typekit mapping" do
            assert_equal [typekit].to_set, loader.typekits_by_type_name['/string']
        end
        it "should register all interface types" do
            assert_equal ['/string'].to_set, loader.interface_typelist
        end
    end

    describe "#deployed_task_model_from_name" do
        it "raises AmbiguousName if there are more than one deployment with a task matching the name" do
            loader.should_receive(:find_deployments_from_deployed_task_name).
                with(task_name = flexmock).
                once.
                and_return([flexmock(name: 'a'), flexmock(name: 'b')])
            assert_raises(OroGen::AmbiguousName) { loader.deployed_task_model_from_name(task_name) }
        end
    end

    describe "#register_typekit_model" do
        attr_reader :typekit, :loader
        before do
            @typekit = OroGen::Spec::Typekit.new(nil, 'test')
            @loader = OroGen::Loaders::Base.new
        end

        it "stores the name of the registered typekit in its type's orogen:typekits metadata" do
            typekit.create_null '/test'
            loader.register_typekit_model(typekit)
            assert_equal ['test'], loader.resolve_type('/test').metadata.get('orogen:typekits')
        end

        it "is available after registration" do
            typekit.create_null '/test'
            loader.register_typekit_model(typekit)
            assert loader.has_typekit?('test')
        end

        describe "opaque-intermediate relations" do
            def self.common(context)
                context.it "stores the links between opaques and intermediates in the metadata" do
                    loader.register_typekit_model(typekit)
                    assert_equal ['/intermediate'], loader.resolve_type('/test').
                        metadata.get('orogen:intermediate_type')
                    assert_equal ['/test'], loader.resolve_type('/intermediate').
                        metadata.get('orogen:intermediate_type_of')
                end
            end

            describe "plain opaques" do
                before do
                    opaque = typekit.create_opaque '/test', 10
                    typekit.create_null '/intermediate'
                    flexmock(typekit).should_receive(:intermediate_type_name_for).
                        with(opaque).and_return('/intermediate')
                end

                common(self)

                it "does not set the orogen:generated_type metadata" do
                    loader.register_typekit_model(typekit)
                    assert_equal [], loader.resolve_type('/intermediate').
                        metadata.get('orogen:generated_type')
                end
            end

            describe "types that contain opaques" do
                before do
                    opaque_t = typekit.create_opaque '/opaque', 10
                    test_t   = typekit.create_compound '/test' do |c|
                        c.add 'field', '/opaque'
                    end
                    typekit.create_null '/field_intermediate'
                    typekit.create_null '/intermediate'
                    flexmock(typekit).should_receive(:intermediate_type_name_for).
                        with(opaque_t).and_return('/field_intermediate')
                    flexmock(typekit).should_receive(:intermediate_type_name_for).
                        with(test_t).and_return('/intermediate')
                end

                common(self)

                it "sets the orogen:generated_type to 'true'" do
                    loader.register_typekit_model(typekit)
                    assert_equal ['true'], loader.resolve_type('/intermediate').
                        metadata.get('orogen:generated_type')
                end
            end
        end
    end

    describe "#imported_typekits_for" do
        attr_reader :registry, :typekit, :definition_typekit
        before do
            @registry = Typelib::CXXRegistry.new
            @typekit = OroGen::Spec::Typekit.new(loader, "typekit", registry, [])
            @definition_typekit = OroGen::Spec::Typekit.new(loader, "definition_typekit", registry, ['/int32_t'])
            loader.register_typekit_model(typekit)
        end

        it "raises DefinitionTypekitNotFound if no loaded typekits define the type" do
            assert_raises(OroGen::DefinitionTypekitNotFound) do
                loader.imported_typekits_for("/Test")
            end
        end

        describe "definition_typekits: false" do
            it "returns the typekits that have the type in their registry" do
                loader.register_typekit_model(definition_typekit)
                assert_equal [typekit, definition_typekit].to_set,
                    loader.imported_typekits_for('/int32_t', definition_typekits: false)
            end
        end
        describe "definition_typekits: true" do
            it "returns the typekits that directly define the type" do
                loader.register_typekit_model(definition_typekit)
                assert_equal [definition_typekit].to_set,
                    loader.imported_typekits_for('/int32_t', definition_typekits: true)
            end
            it "raises DefinitionTypekitNotFound if some typekits define the type, but none of them directly define it" do
                assert_raises(OroGen::DefinitionTypekitNotFound) do
                    loader.imported_typekits_for("/int32_t", definition_typekits: true)
                end
            end
        end
    end
end



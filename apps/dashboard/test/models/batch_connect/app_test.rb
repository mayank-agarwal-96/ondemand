require 'test_helper'

class BatchConnect::AppTest < ActiveSupport::TestCase

  def setup
    OodAppkit.stubs(:clusters).returns(OodCore::Clusters.load_file('test/fixtures/config/clusters.d'))
  end

  def expected_clusters(*args)
    # want the return value to have the same order as *args so OodAppkit.clusters.select won't work
    args.each_with_object([]) do |arg, clusters|
      clusters.append(OodAppkit.clusters[arg.to_s])
    end.compact
  end

  test "app with malformed form.yml" do
    Dir.mktmpdir { |dir|
      r = PathRouter.new(dir)
      r.path.join("form.yml").write("--x-\nnot a valid form yaml")

      app = BatchConnect::App.new(router: r)
      assert ! app.valid?
    }
  end

  test "missing app handled gracefully" do
    Dir.mktmpdir { |dir|
      r = PathRouter.new(dir + "/missing_app")
      app = BatchConnect::App.new(router: r)

      assert ! app.valid?
      assert_match /app does not exist/, app.validation_reason
    }
  end

  test "default app title" do
    Dir.mktmpdir { |dir|
      r = PathRouter.new(dir + "/missing_app")
      assert_equal "Missing App", BatchConnect::App.new(router: r).title
      assert_equal "Missing App: Owens Vdi", BatchConnect::App.new(router: r, sub_app: "owens-vdi").title
    }
  end

  test "form.yml.erb can use __FILE__" do
    Dir.mktmpdir { |dir|
      r = PathRouter.new(dir)
      r.path.join("form.yml.erb").write("---\ntitle: <%= File.expand_path(File.dirname(__FILE__)) %>")

      app = BatchConnect::App.new(router: r)
      assert_equal dir, app.title, "When rendering form.yml.erb __FILE__ doesn't return correct value"
    }
  end

  test "sub_apps_list doesn't crash when local directory inaccessible" do
    begin
      # place in begin/ensure so we can delete the directory after setting
      # back the permissions to 0700 on the local sub directory
      # the normal Dir.mktmpdir {} would result in an exception being thrown
      # when deleting the directories at the end of the test run
      #
      appdir = Pathname.new(Dir.mktmpdir)

      # create local dir but make it inaccessible
      localdir = appdir.join("local")
      localdir.mkdir
      localdir.chmod(0000)

      app = BatchConnect::App.new(router: PathRouter.new(appdir))

      assert 1, app.sub_app_list.count
      assert_equal app, app.sub_app_list.first
    ensure
      localdir.chmod(0700)
      appdir.rmtree
    end
  end

  test "app with multiple clusters" do
    Dir.mktmpdir { |dir|
      r = PathRouter.new(dir)
      r.path.join("form.yml").write("cluster:\n  - owens\n  - pitzer\n  - ruby")

      app = BatchConnect::App.new(router: r)
      assert app.valid?
      assert_equal expected_clusters(:owens, :pitzer), app.clusters # make sure you only allow good clusters
    }
  end

  test "app with a single invalid cluster" do
    Dir.mktmpdir { |dir|
      r = PathRouter.new(dir)
      r.path.join("form.yml").write("cluster:\n  - ruby")

      app = BatchConnect::App.new(router: r)
      assert !app.valid?
      assert_equal [], app.clusters
    }
  end

  test "app with a single valid cluster" do
    Dir.mktmpdir { |dir|
      r = PathRouter.new(dir)
      # note the format here, it's a string not array for backward compatability
      r.path.join("form.yml").write("cluster: \'owens\'")

      app = BatchConnect::App.new(router: r)
      assert app.valid?
      assert_equal [OodCore::Cluster.new({ id: 'owens', job: { foo: 'bar' } })], app.clusters
    }
  end

  test "app with special case of all clusters (*)" do
    Dir.mktmpdir { |dir|
      r = PathRouter.new(dir)
      # note the format here, it's a string not array for backward compatability
      # Also note the quotes, those are nessecary for yaml to parse it correctly
      r.path.join("form.yml").write("cluster: '*'")

      app = BatchConnect::App.new(router: r)
      assert app.valid?
      # have to cast to set here because globs ordering is not gaurenteed.
      assert_equal expected_clusters(:owens, :oakley, :pitzer, :quick).to_set, app.clusters.to_set
    }
  end

  test "app with single glob to get owens" do
    Dir.mktmpdir { |dir|
      r = PathRouter.new(dir)
      r.path.join("form.yml").write("cluster: ow*")

      app = BatchConnect::App.new(router: r)
      assert app.valid?
      assert_equal expected_clusters(:owens), app.clusters
    }
  end

  test "app with multiple globs to get owens and oakley, but not ruby" do
    Dir.mktmpdir { |dir|
      r = PathRouter.new(dir)
      # try to pick up all of them by globs
      r.path.join("form.yml").write("cluster:\n  - ow*\n  - oak*\n  - r*")

      app = BatchConnect::App.new(router: r)
      assert app.valid?
      assert_equal expected_clusters(:owens, :oakley), app.clusters # make sure you only allow good clusters
    }
  end

  test "app with user defined cluster" do
    Dir.mktmpdir { |dir|
      r = PathRouter.new(dir)
      r.path.join("form.yml").write("form:\n  - cluster")

      app = BatchConnect::App.new(router: r)
      # it's valid but there are no clusters. they're user defined and not validated by us
      assert app.valid?
      assert_equal expected_clusters, app.clusters
    }
  end

  test "app with empty configured cluster is not configured with any cluster" do
    Dir.mktmpdir { |dir|
      r = PathRouter.new(dir)
      r.path.join("form.yml").write("cluster: \"\"")

      app = BatchConnect::App.new(router: r)
      # it's valid but there are no clusters. Empty configurations are the same as
      # user defined
      assert app.valid?
      assert_equal [], app.configured_clusters
      assert_equal [], app.clusters
    }
  end

  test "app disregards empty cluster strings" do
    Dir.mktmpdir { |dir|
      r = PathRouter.new(dir)
      # note the empty string and the string with whitespace
      r.path.join("form.yml").write("cluster:\n  - owens\n  - \"\"\n  - \"  \"")

      app = BatchConnect::App.new(router: r)

      assert app.valid?
      # only owens gets through
      assert_equal [ 'owens' ], app.configured_clusters
      assert_equal expected_clusters(:owens), app.clusters
    }
  end

  test "app does not include quick_pitzer when given pitzer" do
    clusters = OodAppkit.clusters.to_a +
      [
        OodCore::Cluster.new({ id: 'pitzer', job: { foo: 'bar' } }),
        OodCore::Cluster.new({ id: 'quick_pitzer', job: { foo: 'bar' } }),
        OodCore::Cluster.new({ id: 'owens_login', job: { foo: 'bar' } }),
        OodCore::Cluster.new({ id: '_owens_', job: { foo: 'bar' } }),
        OodCore::Cluster.new({ id: '_pitzer_', job: { foo: 'bar' } }),
        OodCore::Cluster.new({ id: 'pit', job: { foo: 'bar' } }),
        OodCore::Cluster.new({ id: 'owen', job: { foo: 'bar' } })
      ]

    OodAppkit.stubs(:clusters).returns(OodCore::Clusters.new(clusters))

    Dir.mktmpdir { |dir|
      r = PathRouter.new(dir)
      r.path.join("form.yml").write("cluster:\n  - \"owens\"\n  - \"pitzer\"")

      app = BatchConnect::App.new(router: r)
      assert app.valid?
      assert_equal expected_clusters(:owens, :pitzer), app.clusters
    }
  end

  test "staged root is available to the submit options" do
    r = PathRouter.new("test/fixtures/sys_with_interactive_apps/bc_jupyter")
    app = BatchConnect::App.new(router: r)

    Dir.mktmpdir do |dir|
      opts = app.submit_opts(app.build_session_context, staged_root: dir)
      assert_equal opts[:script][:error_path], "#{dir}/error.log"
    end
  end

  test "select widgets with no options values throws error" do
    r = PathRouter.new("test/fixtures/sys_with_interactive_apps/broken_app")
    app = BatchConnect::App.new(router: r)

    Dir.mktmpdir do |dir|
      exception = assert_raise StandardError do 
        app.submit_opts(app.build_session_context, staged_root: dir)
      end
      assert_equal "The form.yml has missing options in the node_type form field.", exception.message
    end
  end

  test "bad submit.yml.erb files write submit.yml" do
    r = PathRouter.new("test/fixtures/sys_with_interactive_apps/bc_paraview")
    app = BatchConnect::App.new(router: r)
    expected_file = <<~HEREDOC
      ---
      script:
        native:
        bad_yml_syntax
    HEREDOC

    Dir.mktmpdir do |dir|
      assert_raise Psych::SyntaxError do 
        app.submit_opts(app.build_session_context, staged_root: dir)
      end
      assert_equal expected_file, File.read("#{dir}/submit.yml")
    end
  end
end

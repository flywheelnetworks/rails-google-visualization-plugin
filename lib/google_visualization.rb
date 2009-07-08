# GoogleVisualization
module GoogleVisualization
  class GoogleVis

    attr_reader :collection, :collection_methods, :options, :size, :helpers, :procedure_hash, :name
    @@vis_types = {
      'motionchart' => 'MotionChart',
      'linechart' => 'LineChart',
      'annotatedtimeline' => 'AnnotatedTimeLine',
      'table' => 'Table',
      'geomap' => 'GeoMap'
    }
    
    def columns
      case @vis_type
      when 'motionchart'
        [:label, :time, :x, :y, :color, :bubble_size]
      when 'annotatedtimeline'
        [:time]
      else
        []
      end
    end
        
    def method_missing(method, *args, &block)
      if self.columns.include?(method)
        procedure_hash[method] = [args[0], block]
      else
        helpers.send(method, *args, &block)
      end
    end
    
    def initialize(view_instance, collection, vis_type, options={}, *args)
      @helpers = view_instance
      @collection = collection
      @vis_type = vis_type
      @collection_methods = collection_methods
      @options = options.reverse_merge({:width => 600, :height => 300})
      @columns = []
      @rows = []
      if self.columns.include?(:color)
        @procedure_hash = {:color => ["Department", lambda {|item| label_to_color(@procedure_hash[:label][1].call(item)) }] }
      else
        @procedure_hash = {}
      end
      @size = collection.size
      @name = "google_vis_#{self.object_id.to_s.gsub("-","")}"
      @labels = {}
      @color_count = 0
    end

    def header
      content_tag(:div, "", :id => name, :style => "width: #{options[:width]}px; height: #{options[:height]}px;")
    end

    def body
      javascript_tag do
        "var data = new google.visualization.DataTable();\n" +
        "data.addRows(#{size});\n" +
        render_columns +
	      render_rows +
        "var #{name} = new google.visualization.#{@@vis_types[@vis_type]}(document.getElementById('#{name}'));\n" +
        "#{name}.draw(data, #{options.to_json});"
      end
    end

    def render
      header + "\n" + body
    end

    def render_columns
      if required_methods_supplied?
        self.columns.each { |c| @columns << google_vis_add_column(procedure_hash[c]) }
        procedure_hash.each { |key, value| @columns[key] = google_vis_add_column(value) if not self.columns.include?(key) }
        @columns.join("\n")
      end
    end

    def render_rows
      if required_methods_supplied?
        collection.each_with_index do |item, index|
          self.columns.each_with_index {|name,column_index| @rows << google_vis_set_value(index, column_index, procedure_hash[name][1].call(item)) }
          procedure_hash.each {|key,value| @rows << google_vis_set_value(index, key, procedure_hash[key][1].call(item)) unless self.columns.include?(key) }
        end
        @rows.join("\n")
      end
    end

    def required_methods_supplied?
      self.columns.each do |key|
        unless procedure_hash.has_key? key
          raise "GoogleVis Must have the #{key} method called before it can be rendered"
	      end
      end
    end

    def google_vis_add_column(title_proc_tuple)
      title = title_proc_tuple[0]
      procedure = title_proc_tuple[1]
      "data.addColumn('#{google_type(procedure)}','#{title}');\n"
    end
  
    def google_vis_set_value(row, column, value)
      "data.setValue(#{row}, #{column}, #{Mappings.ruby_to_javascript_object(value)});\n"
    end
  
    def google_type(procedure)
      Mappings.ruby_to_google_type(procedure.call(collection[0]).class)
    end

    def google_formatted_value(value)
      Mappings.ruby_to_javascript_object(value)
    end
  
    def label_to_color(label)
      hashed_label = label.downcase.gsub(" |-","_").to_sym
      if @labels.has_key? hashed_label
        @labels[hashed_label]
      else
        @color_count += 1
	      @labels[hashed_label] = @color_count
      end
    end

    def extra_column(title, &block)
      procedure_hash[procedure_hash.size] = [title, block]
    end

  end

  module Mappings
    def self.ruby_to_google_type(type)
      type_hash = {
        :String => "string",
        :Fixnum => "number",
        :Float => "number",
        :Date => "date",
        :Time => "datetime",
        :NilClass => 'string',
      }
      type_hash[type.to_s.to_sym]
    end

    def self.ruby_to_javascript_object(value)
      value_hash = {
        :String => lambda {|v| "'#{v}'"},
        :Date => lambda {|v| "new Date(#{v.to_s.gsub("-",",")})"},
        :Fixnum => lambda {|v| v },
	      :Float => lambda {|v| v },
	      :NilClass => lambda {|v| 'null'},
      }
      value_hash[value.class.to_s.to_sym].call(value)
    end
  end

  module Helpers
    # types: an array of packages like: 'motionchart', 'geomap', etc
    def setup_google_vis(types)
      packages = '"' + types.to_a.join('", "') + '"'
      "<script type=\"text/javascript\" src=\"http://www.google.com/jsapi\"></script>\n" +
      javascript_tag("google.load(\"visualization\", \"1\", {packages:[#{packages}]});")
    end

    def google_vis_for(collection, vis_type, options={}, *args, &block)
      google_vis = GoogleVis.new(self, collection, vis_type, options)
      yield google_vis
      concat(google_vis.render)
    end
  end
end

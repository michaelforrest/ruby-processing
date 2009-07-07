require "#{File.dirname(__FILE__)}/base.rb"

module Processing  
  
  # A sketch loader, observer, and reloader, to tighten 
  # the feedback between code and effect.
  class Watcher
    HARNESS_CLASS_NAMES = Module.constants
    HARNESS_CLASS_FILES = $".map{ |path| File.expand_path(path) }
    # Sic a new Processing::Watcher on the sketch
    def initialize
      @files = ARGV.map { |path|
        Dir["#{path}/**/*.rb"]
      }.flatten
      @files << Processing::SKETCH_PATH
      @time = Time.now
      start_watching
    end
    
    
    # Kicks off a thread to watch the sketch, reloading Ruby-Processing
    # and restarting the sketch whenever it changes.
    def start_watching
      
      start_thread! unless $app
      
      thread = Thread.start do
        loop do
          #if file_mtime > @time
          if any_files_changed?
            wipe_out_current_app!
            GC.start
            start_thread!
          end
          sleep 0.33
        end
      end
      thread.join
    end
    def start_thread!
      @runner = Thread.start do
        begin
          Processing.load_and_run_sketch
        rescue Exception=>e
          puts "\033[0;31m" # RED
          puts e
          puts "\e[0m" # NORMAL
          puts e.backtrace
          raise e
        end
      end
    end
    
    def any_files_changed?
      @files.each do |file|
        if File.stat(file).mtime > @time
          puts "#{file} changed"
          @time = File.stat(file).mtime
          return true 
        end
      end
      false
    end
    
    # Used to completely remove all traces of the current sketch, 
    # so that it can be loaded afresh. Go down into modules to find it, even.
    # MF: expanded to include paths added in the command line 
    # so that it works with sketches containing multiple files
    def wipe_out_current_app!
      @runner.kill if @runner.alive?
      app = $app
      return unless app
      app.no_loop
      # Wait for the animation thread to finish rendering
      sleep 0.075
      app.close
 
      wipe_out_app_classes! (app)
      
    end
    
    def wipe_out_app_classes! app
      class_names_to_remove = Module.constants - HARNESS_CLASS_NAMES #+ [app.class.to_s]
      puts "removing constants #{class_names_to_remove.inspect}"
      class_names_to_remove.each do |class_name|
        constant_names = class_name.to_s.split(/::/)
        app_class_name = constant_names.pop
        app_class = constant_names.inject(Object) {|moduul, name| moduul.send(:const_get, name) }
        app_class.send(:remove_const, app_class_name)
      end
      
      # $" is the array of required files that have already been loaded
      # These paths are stored relatively
      # Convert to absolute paths and then remove so that requires are triggered again 
      $".replace $".map{ |path| File.expand_path(path) }
      class_files_to_remove = $" - HARNESS_CLASS_FILES
      puts "removing required files #{class_files_to_remove.inspect}"
      $".replace $" - class_files_to_remove
  
    end
    
    
  end
end

Processing::Watcher.new

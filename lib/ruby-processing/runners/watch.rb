require "#{File.dirname(__FILE__)}/base.rb"

module Processing  
  
  # A sketch loader, observer, and reloader, to tighten 
  # the feedback between code and effect.
  class Watcher
    HARNESS_CLASS_NAMES =  ["Marshal", "JavaUtilities", "IndexError", "Kernel", "Class", "RubyLex", "Symbol", "TOPLEVEL_BINDING", "IRB", "FALSE", "SIGNALS", "FileTest", "JRuby", "Readline", "STDOUT", "LoadError", "ThreadGroup", "RUBY_PLATFORM", "MatchData", "Kconv", "VERSION", "FalseClass", "Integer", "ScriptError", "RangeError", "StandardError", "Struct", "SystemExit", "ARGF", "ArrayJavaProxy", "Time", "ENV_JAVA", "RUBY_RELEASE_DATE", "SyntaxError", "ArrayJavaProxyCreator", "NoMethodError", "RUBY_ENGINE", "Comparable", "Precision", "RELEASE_DATE", "JavaSignal", "FloatDomainError", "GC", "Numeric", "UnboundMethod", "Signal", "Bignum", "String", "Java", "ZeroDivisionError", "PLATFORM", "ArgumentError", "Math", "Regexp", "NameError", "File", "TrueClass", "NoMemoryError", "Fatal", "TRUE", "Dir", "NilClass", "RUBY_PATCHLEVEL", "Process", "STDIN", "IOError", "ConcreteJavaProxy", "STDERR", "SignalException", "JavaProxy", "Array", "Continuation", "SLex", "SystemStackError", "NotImplementedError", "Module", "Exception2MessageMapper", "ObjectSpace", "Fixnum", "IO", "Enumerable", "ENV", "Object", "RP5_ROOT", "JavaArrayUtilities", "RubyToken", "Binding", "RegexpError", "Boot", "JRUBY_VERSION", "Hash", "ThreadError", "SKETCH_ROOT", "JavaInterfaceExtender", "LocalJumpError", "JavaProxyMethods", "Proc", "Thread", "SystemCallError", "JavaInterfaceTemplate", "Range", "NativeException", "ROOT", "Data", "SecurityError", "ARGV", "Errno", "Method", "TypeError", "RuntimeError", "NIL", "Float", "RUBY_VERSION", "Exception", "Processing", "JavaPackageModuleTemplate", "InterfaceJavaProxy", "ConcurrencyError", "Interrupt", "EOFError", "MatchingData"]
    
    # Sic a new Processing::Watcher on the sketch
    def initialize
      @files = ARGV.map { |path|
        Dir["#{path}/**/*.rb"]
      }.flatten
      @files << Processing::SKETCH_PATH
      @time = Time.now
      # Doesn't work well enough for now.
      # record_state_of_ruby
      start_watching
    end
    
    
    # Kicks off a thread to watch the sketch, reloading Ruby-Processing
    # and restarting the sketch whenever it changes.
    def start_watching
      @runner = Thread.start { Processing.load_and_run_sketch } unless $app
      thread = Thread.start do
        loop do
          #if file_mtime > @time
          if any_files_changed?
            wipe_out_current_app!
            # Taking it out the reset until it can be made to work more reliably
            # rewind_to_recorded_state
            GC.start
            @runner = Thread.start { 
              Processing.load_and_run_sketch 
            }
          end
          sleep 0.33
        end
      end
      thread.join
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
      class_names_to_remove = Module.constants - HARNESS_CLASS_NAMES + [app.class.to_s]
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
      class_names_to_remove.replace class_names_to_remove.map{ |path| File.expand_path(path) }
      $".replace($" - class_names_to_remove)
  
    end
    
    # The following methods were intended to make the watcher clean up all code
    # loaded in from the sketch, gems, etc, and have them be reloaded properly
    # when the sketch is.... but it seems that this is neither a very good idea
    # or a very possible one. If you can make the scheme work, please do, 
    # otherwise the following methods will probably be removed soonish.
    
    # Do the best we can to take a picture of the current Ruby interpreter.
    # For now, this means top-level constants and loaded .rb files.
    def record_state_of_ruby
      @saved_constants  = Object.send(:constants).dup
      @saved_load_paths = $LOAD_PATH.dup
      @saved_features   = $LOADED_FEATURES.dup
      @saved_globals    = Kernel.global_variables.dup
    end
    
    
    # Try to go back to the recorded Ruby state.
    def rewind_to_recorded_state
      new_constants  = Object.send(:constants).reject {|c| @saved_constants.include?(c) }
      new_load_paths = $LOAD_PATH.reject {|p| @saved_load_paths.include?(p) }
      new_features   = $LOADED_FEATURES.reject {|f| @saved_features.include?(f) }
      new_globals    = Kernel.global_variables.reject {|g| @saved_globals.include?(g) }
      
      Processing::App.recursively_remove_constants(Object, new_constants)
      new_load_paths.each {|p| $LOAD_PATH.delete(p) }
      new_features.each {|f| $LOADED_FEATURES.delete(f) }
      new_globals.each do |g| 
        begin
          eval("#{g} = nil") # There's no way to undef a global variable in Ruby
        rescue NameError => e
          # Some globals are read-only, and we can't set them to nil.
        end
      end
    end
    
    
    # Used to clean up declared constants in code that needs to be reloaded.
    def recursively_remove_constants(base, constant_names)
      constants = constant_names.map {|name| base.const_get(name) }
      constants.each_with_index do |c, i|
        java_obj = Java::JavaLang::Object
        constants[i] = constant_names[i] = nil if c.respond_to?(:ancestors) && c.ancestors.include?(java_obj)
        constants[i] = nil if !c.is_a?(Class) && !c.is_a?(Module)
      end
      constants.each {|c| recursively_remove_constants(c, c.constants) if c }
      constant_names.each {|name| base.send(:remove_const, name.to_sym) if name }
    end
    
  end
end

Processing::Watcher.new

# Parent module containing all variables defined as part of virtual_keywords
module VirtualKeywords

  # Utility functions used to inspect the class hierarchy, and to view
  # and modify methods of classes.
  class ClassReflection
    # Get the subclasses of a given class.
    #
    # Arguments:
    #   parent: (Class) the class whose subclasses to find.
    #
    # Returns:
    #   (Array) all classes which are subclasses of parent.
    def self.subclasses_of_class(parent)
      ObjectSpace.each_object(Class).select { |klass|
        klass < parent
      }
    end

    # Given an array of base classes, return a flat array of all their
    # subclasses.
    #
    # Arguments:
    #   klasses: (Array[Class]) an array of classes
    #
    # Returns:
    #   (Array) All classes that are subclasses of one of the classes in klasses,
    #           in a flattened array.
    def self.subclasses_of_classes(klasses)
      klasses.map { |klass|
        subclasses_of_class klass
      }.flatten
    end

    # Get the instance_methods of a class.
    #
    # Arguments:
    #   klass: (Class) the class.
    #
    # Returns:
    #   (Hash[Symbol, Array]) A hash, mapping method names to the results of
    #                         ParseTree.translate.
    def self.instance_methods_of(klass)
      methods = {}
      klass.instance_methods(false).each do |method_name|
        translated = ParseTree.translate(klass, method_name)
        methods[method_name] = translated
      end

      methods
    end

    # Install a method on a class. When object.method_name is called
    # (for objects in the class), have them run the given code.
    # TODO Should it be possible to recover the old method?
    # How would that API look?
    #
    # Arguments:
    #   klass: (Class) the class which should be modified.
    #   method_code: (String) the code for the method to install, of the format:
    #       def method_name(args)
    #         ...
    #       end
    def self.install_method_on_class(klass, method_code)
      klass.class_eval method_code
    end

    # Install a method on an object. When object.method_name is called,
    # runs the given code.
    #
    # This function can also be used for classmethods. For example, if you want
    # to rewrite Klass.method_name (a method on Klass, a singleton Class),
    # call this method (NOT install_method_on_class, that will modifiy objects
    # created through Klass.new!)
    #
    # Arguments:
    #   object: (Object) the object instance that should be modified.
    #   method_code: (String) the code for the method to install, of the format:
    #       def method_name(args)
    #         ...
    #       end
    def self.install_method_on_instance(object, method_code)
      object.instance_eval method_code
    end
  end

  # Deeply copy an array.
  #
  # Arguments:
  #   array: (Array[A]) the array to copy. A is any arbitrary type.
  #
  # Returns:
  #   (Array[A]) a deep copy of the original array.
  def self.deep_copy_array(array)
    Marshal.load(Marshal.dump(array))
  end

  # Object that virtualizes keywords.
  class Virtualizer
    # Initialize a Virtualizer
    # 
    # Arguments:
    #   A Hash with the following arguments (all optional):
    #   for_classes: (Array[Class]) an array of classes. All methods of objects
    #       created from the given classes will be virtualized (optional, the
    #       default is an empty Array).
    #   for_instances: (Array[Object]) an array of object. All of these objects'
    #       methods will be virtualized
    #       (optional, the default is an empty Array).
    #   for subclasses_of: (Array[Class]) an array of classes. All methods of
    #       objects created from the given classes' subclasses (but NOT those
    #       from the given classes) will be virtualized.
    #   if_rewriter: (IfRewriter) the SexpProcessor descendant that
    #       rewrites "if"s in methods (optional, the default is
    #       IfRewriter.new).
    #   and_rewriter: (AndRewriter) the SexpProcessor descendant that
    #       rewrites "and"s in methods (optional, the default is
    #       AndRewriter.new).
    #   or_rewriter: (OrRewriter) the SexpProcessor descendant that
    #       rewrites "or"s in methods (optional, the default is
    #       OrRewriter.new).
    #   while_rewriter: (WhileRewriter) the SexpProcessor descendant that
    #       rewrites "while"s in methods (optional, the default is
    #       WhileRewriter.new).
    #   sexp_processor: (SexpProcessor) the sexp_processor that can turn
    #       ParseTree results into sexps (optional, the default is
    #       SexpProcessor.new).
    #   sexp_stringifier: (SexpStringifier) an object that can turn sexps
    #       back into Ruby code (optional, the default is
    #       SexpStringifier.new).
    #   rewritten_keywords: (RewrittenKeywords) a repository for keyword
    #       replacement lambdas (optional, the default is REWRITTEN_KEYWORDS).
    #   class_reflection: (Class) an object that provides methods to modify the
    #       methods of classes (optional, the default is ClassReflection).
    def initialize(input_hash)
      @for_classes = input_hash[:for_classes] || []
      @for_instances = input_hash[:for_instances] || []
      @for_subclasses_of = input_hash[:for_subclasses_of] || []
      @if_rewriter = input_hash[:if_rewriter] || IfRewriter.new
      @and_rewriter = input_hash[:and_rewriter] || AndRewriter.new
      @or_rewriter = input_hash[:or_rewriter] || OrRewriter.new
      @while_rewriter = input_hash[:while_rewriter] || WhileRewriter.new
      @sexp_processor = input_hash[:sexp_processor] || SexpProcessor.new
      @sexp_stringifier = input_hash[:sexp_stringifier] || SexpStringifier.new
      @rewritten_keywords =
          input_hash[:rewritten_keywords] || REWRITTEN_KEYWORDS
      @class_reflection = input_hash[:class_reflection] || ClassReflection
    end

    # Helper method to rewrite code.
    #
    # Arguments:
    #   translated: (Array) the output of ParseTree.translate on the original
    #       code
    #   rewriter: (SexpProcessor) the object that will rewrite the sexp, to
    #       virtualize the keywords.
    def rewritten_code(translated, rewriter)
      sexp = @sexp_processor.process(
          VirtualKeywords.deep_copy_array(translated))
      new_code = @sexp_stringifier.stringify(
          rewriter.process(sexp))
    end

    # Helper method to rewrite all methods of an object.
    #
    # Arguments:
    #   instance: (Object) the object whose methods will be rewritten.
    #   keyword: (Symbol) the keyword to virtualize.
    #   rewriter: (SexpProcessor) the object that will do the rewriting.
    #   block: (Proc) the lambda that will replace the keyword.
    def rewrite_methods_of_instance(instance, keyword, rewriter, block)
      @rewritten_keywords.register_lambda_for_object(instance, keyword, block)

      methods = @class_reflection.instance_methods_of instance.class
      methods.each do |name, translated|
        new_code = rewritten_code(translated, rewriter)
        @class_reflection.install_method_on_instance(instance, new_code)
      end
    end

    # Helper method to rewrite all methods of objects from a class.
    #
    # Arguments:
    #   klass: (Class) the class whose methods will be rewritten.
    #   keyword: (Symbol) the keyword to virtualize.
    #   rewriter: (SexpProcessor) the object that will do the rewriting.
    #   block: (Proc) the lambda that will replace the keyword.
    def rewrite_methods_of_class(klass, keyword, rewriter, block)
      @rewritten_keywords.register_lambda_for_class(klass, keyword, block)

      methods = @class_reflection.instance_methods_of klass
      methods.each do |name, translated|
        new_code = rewritten_code(translated, rewriter)
        @class_reflection.install_method_on_class(klass, new_code)
      end
    end

    # Helper method to virtualize a keyword (rewrite with the given block)
    #
    # Arguments:
    #   keyword: (Symbol) the keyword to virtualize.
    #   rewriter: (SexpProcessor) the object that will do the rewriting.
    #   block: (Proc) the lambda that will replace the keyword.
    def virtualize_keyword(keyword, rewriter, block)
      @for_instances.each do |instance|
        rewrite_methods_of_instance(instance, keyword, rewriter, block)  
      end 

      @for_classes.each do |klass|
        rewrite_methods_of_class(klass, keyword, rewriter, block)
      end

      subclasses = @class_reflection.subclasses_of_classes @for_subclasses_of
      subclasses.each do |subclass|
        rewrite_methods_of_class(subclass, keyword, rewriter, block)
      end
    end

    # Rewrite "if" expressions.
    #
    # Arguments:
    #   &block: The block that will replace "if"s in the objects being
    #       virtualized
    def virtual_if(&block)
      virtualize_keyword(:if, @if_rewriter, block)
    end

    # Rewrite "and" expressions.
    #
    # Arguments:
    #   &block: The block that will replace "and"s in the objects being
    #       virtualized
    def virtual_and(&block)
      virtualize_keyword(:and, @and_rewriter, block)
    end

    # Rewrite "or" expressions.
    #
    # Arguments:
    #   &block: The block that will replace "or"s in the objects being
    #       virtualized
    def virtual_or(&block)
      virtualize_keyword(:or, @or_rewriter, block)
    end

    # Rewrite "while" expressions.
    #
    # Arguments:
    #   &block: The block that will replace "while"s in the objects being
    #       virtualized
    def virtual_while(&block)
      virtualize_keyword(:while, @while_rewriter, block)
    end
  end
end

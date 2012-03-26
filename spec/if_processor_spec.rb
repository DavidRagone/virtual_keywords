require 'spec_helper'

# TODO Inspect the printed output, figure out how to rewrite the sexp
describe 'if_processor' do

  before :each do
    @sexp_processor = SexpProcessor.new

    def method_to_sexp(klass, method)
      translated = ParseTree.translate(klass, method)

      @sexp_processor.process translated
    end

    @greet_sexp = method_to_sexp(Greeter, :greet)
    @greet_changed_sexp = method_to_sexp(Greeter, :greet_changed)

    @if_processor = IfProcessor.new
  end

  #it 'compares sexps of manually translated if' do
    #puts 'before translation'
    #p @greet_sexp
    #puts ''

    #puts 'after translation'
    #p @greet_changed_sexp
    #puts ''
  #end

  #it 'turns a method with block code into a sexp' do
    #count_sexp = method_to_sexp(Greeter, :count_to_ten)
    #p count_sexp
  #end

  it 'should process greet' do
    result = @if_processor.process @greet_sexp    

    # Visually inspecting this result, it appears to be right
    code_result = sexp_to_string result
    #puts code_result # Uncomment this to see the translated code.

    # my_if does not change the behavior, so both the old and new
    # code should produce the same result (greet is referentially
    # transparent)
    greeter = Greeter.new true
    old_result = greeter.greet
    greeter.instance_eval code_result # Put in the new method
    new_result = greeter.greet

    new_result.should eql old_result
  end
end

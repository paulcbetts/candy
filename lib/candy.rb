require 'candy/exceptions'
require 'candy/crunch'
require 'candy/wrapper'

# Mix me into your classes and Mongo will like them!
module Candy
  
  module ClassMethods
    include Crunch::ClassMethods
    
    # Retrieves an object from Mongo by its ID and returns it.  Returns nil if the ID isn't found in Mongo.
    def find(id)
      if collection.find_one(id)
        self.new({:_candy => id})
      end
    end
    
    # Retrieves a single object from Mongo by its search attributes, or nil if it can't be found.
    def first(conditions={})
      options = extract_options(conditions)
      if record = collection.find_one(conditions, options)
        find(record["_id"])
      else
        nil
      end
    end
    
    # Retrieves all objects matching the search attributes as an Enumerator (even if it's an empty one).
    # The option fields from Mongo::Collection#find can be passed as well, and will be extracted from the 
    # condition set if they're found.
    def all(conditions={})
      options = extract_options(conditions)
      cursor = collection.find(conditions, options)
      Enumerator.new do |yielder|
        while record = cursor.next_document do
          yielder.yield find(record["_id"])
        end
      end  
    end
    
  private
    # Returns a hash of options matching those enabled in Mongo::Collection#find, if any of them exist
    # in the set of search conditions.
    def extract_options(conditions)
      options = {:fields => []}
      [:fields, :skip, :limit, :sort, :hint, :snapshot, :timeout].each do |option|
        options[option] = conditions.delete(option) if conditions[option]
      end
      options
    end
    
  end
  
  module InstanceMethods
    include Crunch::InstanceMethods
    
    # We push ourselves into the DB before going on with our day.
    def initialize(*args, &block)
      @__candy = check_for_candy(args) || self.class.collection.insert({})
      super
    end

    # Shortcut to the document ID.
    def id
      @__candy
    end
    
    # Candy's magic ingredient. Assigning to any unknown attribute will push that value into the Mongo collection.
    # Retrieving any unknown attribute will return that value from this record in the Mongo collection.
    def method_missing(name, *args, &block)
      if name =~ /(.*)=$/  # We're assigning
        set $1, Wrapper.wrap(args[0])
      else
        Wrapper.unwrap(self.class.collection.find_one(@__candy, :fields => [name.to_s])[name.to_s])
      end
    end
    
    # Given either a property/value pair or a hash (which can contain several property/value pairs), sets those
    # values in Mongo using the atomic $set. The first form is functionally equivalent to simply using the
    # magic assignment operator; i.e., `me.set(:foo, 'bar')` is the same as `me.foo = bar`.
    def set(*args)
      if args.length > 1  # This is the property/value form
        hash = {args[0] => args[1]}
      else
        hash = args[0]
      end
      update '$set' => hash
    end
    
    # Given a Candy array property, appends a value or values to the end of that array using the atomic $push.  
    # (Note that we don't actually check the property to make sure it's an array and $push is valid. If it isn't, 
    # this operation will silently fail.)
    def push(property, *values)
      values.each do |value|
        update '$push' => {property => Wrapper.wrap(value)}
      end
    end
    
    # Given a Candy integer property, increments it by the given value (which defaults to 1) using the atomic $inc.
    # (Note that we don't actually check the property to make sure it's an integer and $inc is valid. If it isn't, 
    # this operation will silently fail.)
    def inc(property, increment=1)
      update '$inc' => {property => increment}
    end
  private
  
    # Returns the secret decoder ring buried in the arguments to "new"
    def check_for_candy(args)
      if (candidate = args.pop).is_a?(Hash) and candidate[:_candy]
        candidate[:_candy]
      else # This must not be for us, so put it back  
        args.push candidate if candidate
        nil
      end
    end
    
    # Updates the Mongo document with the given element or elements.
    def update(element)
      self.class.collection.update({"_id" => @__candy}, element)
    end
    
  end
  
  def self.included(receiver)
    receiver.extend         ClassMethods
    receiver.send :include, InstanceMethods
  end
end
Add faceted search to your Meteor project, using Mongo.

    if Meteor.isServer
      Facets.configure MyCollection,
        field1: String
        field2: [String]
    
      Meteor.publish 'myCollection', (field1, field2) ->
        check field1, String
        check field2, [String]
        MyCollection.findWithFacets({field1: field1, field2: {$in: field2}})
    
    if Meteor.isClient
      Meteor.subscribe 'myCollection', 'value1', []
    
      Facets.findOne({collection: 'myCollection'})?.facets


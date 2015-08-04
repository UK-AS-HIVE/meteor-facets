Add faceted search to your Meteor project, using Mongo.
Individual facets are in an array of objects of the form
`fieldName: [ { name: 'value1', count: 1}, { name: 'value2', count: 3 }, { name: 'value3', count: 16 }, { name: null, count: 10 } ]`

A facet name of `null` counts documents whose field value is an empty array.

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


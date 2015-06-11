Add faceted search to your Meteor project, using Mongo.

    if Meteor.isServer
      Facets.configure MyCollection,
        field1: String
        field2: [String]
    
    Facets.find({collection: 'myCollection'})


Add faceted search to your Meteor project, using Mongo.

    if Meteor.isServer
      Facets.configure MyCollection,
        collectionField1: String
        collectionFiled2: [String]
    
    Facets.find({collection: 'myCollection'})


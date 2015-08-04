Facets = new Mongo.Collection 'facets'
#@Facets.attachSchema new SimpleSchema
#  facet:
#    type: String
#    unique: true
#    index: 1
#  'counts.status':
#    type: [Object]
#  'counts.status.$.name':
#    type: String
#  'counts.status.$.count':
#    type: Number
#  'counts.tags':
#    type: [Object]
#  'counts.tags.$.name':
#    type: String
#  'counts.tags.$.count':
#    type: Number

if Meteor.isServer
  #Meteor.startup ->
  #  if Npm.require('cluster').isMaster
  #    ready = false
  #    refreshFacetQueues = (queues) ->
  #      if ready
  #        Facets.remove facet: $in: _.map queues, (q) ->
  #          new RegExp "^queueName:#{q}"
  #        console.log 'forcing recreation of facets for', queues
  #    Tickets.find({},{fields:{queueName:1,status:1,tags:1}}).observe
  #      added: (doc) ->
  #        refreshFacetQueues doc.queueName
  #      changed: (newDoc, oldDoc) ->
  #        refreshFacetQueues _.union newDoc.queueName, oldDoc.queueName
  #      removed: (oldDoc) ->
  #        refreshFacetQueues oldDoc.queueName
  #    ready = true
  #
  #  e.g.:
  #  Facets.configure Tickets,
  #    tags: []
  #    status: String
  #
  Facets.configure = (collection, configuration) ->
    check collection, Mongo.Collection

    fields = _.keys configuration

    # TODO: split this so facet fields can be recomputed independent of each other
    collection.computeFacets = (selector) ->
      check selector, Object

      facets = {}
      _.each fields, (field) ->
        pipeline = []
        pipeline.push {$match: selector}
        if _.isArray configuration[field]
          a = { $project: {} }
          # Null values are replaced with an array containing 'null' for unwind.
          a.$project["#{field}"] = { $ifNull: [ "$#{field}", [null] ] }
          pipeline.push a
          # And the same with empty arrays.
          a.$project["#{field}"] = { $cond: [ { $eq: [ "$#{field}", [] ] }, [null], "$#{field}"] }
          pipeline.push a
          console.log collection.aggregate(pipeline)
          pipeline.push {$unwind: "$#{field}"}
        pipeline.push {$group: {_id: "$#{field}", count: {$sum: 1}}}
        facets[field.replace(/\./g, '-')] = _.map collection.aggregate(pipeline), (s) ->
          {name: s._id, count: s.count}
      return facets

    # Adapt collection.find() so that finds from within publish functions automatically
    # regenerate facets when needed.
    collection.findWithFacets = (selector) ->
      selector = selector || {}

      stringify = Npm.require 'json-stable-stringify'
      facetString = stringify selector
      ready = false
      Facets.upsert {collection: collection._name, facetString: facetString},
        $set:
          facets: collection.computeFacets selector
      #cursor = Facets.find {collection: collection._name, facetString: facetString}
      cursor = collection.find.apply(collection, arguments)

      refresh = (doc) ->
        if ready
          # Force regeneration of a facet whenever updated
          console.log "forcing facet regeneration for #{collection._name} #{facetString} because doc #{doc._id} changed"
          Facets.remove {collection: collection._name, facetString: facetString}

      cursor.observe
        added: refresh
        changed: (n, o) -> refresh _.union n, o
        removed: refresh

      facetCursor = Facets.find({collection: collection._name, facetString: facetString})
      facetCursor.observe
        removed: (doc) ->
          console.log "regenerating facets for #{collection._name}, #{facetString}"
          Facets.upsert {collection: collection._name, facetString: facetString},
            $set:
              facets: collection.computeFacets selector
      ready = true


      return [cursor, facetCursor]


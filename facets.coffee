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

@Filter =
  toMongoSelector: (filter) ->
    mongoFilter = {}
    if typeof filter.queueName is 'string'
      mongoFilter.queueName = filter.queueName
    else if filter.queueName is null
      return
    else
      mongoFilter.queueName = {$in: filter.queueName}
    userIds = []
    if filter.user?
      userIds = filter.user.split(',').map (x) ->
        Meteor.users.findOne({username: x})?._id
      userFilter = [
        { authorName: {$in: filter.user.split(',')}},
        { associatedUserIds: {$in: userIds}},
        { authorId: {$in: userIds}}
      ]
    if filter.userId?
      selfFilter = [
          { associatedUserIds: filter.userId},
          { authorId: filter.userId}
      ]
    if filter.search?.trim().length
      searchFilter = [
        { title: new RegExp(filter.search.replace(',','|'), 'i') },
        { body: new RegExp(filter.search.replace(',','|'), 'i') }
      ]
    _.each [userFilter, searchFilter, selfFilter], (x) ->
      if x?.length > 0
        unless mongoFilter['$and'] then mongoFilter['$and'] = []
        mongoFilter['$and'].push {$or: x}
    if filter.status?
      if filter.status.charAt(0) is '!'
        status = filter.status.substr(1)
        mongoFilter.status = {$ne: status}
      else
        mongoFilter.status = filter.status || ''
    if filter.tag?
      tags = filter.tag.split(',')
      sorted = _.sortBy(tags).join(',')
      mongoFilter.tags = {$all: tags}
    return mongoFilter

  toFacetString: (filter) ->
    check filter, Object
    if typeof filter.queueName is 'string'
      facetPath = "queueName:#{filter.queueName}"
    else
      facetPath = "queueName:#{filter.queueName?.join(',')}"
    if filter.search?.trim().length
      facetPath += "|search:#{filter.search}"
    if filter.status?.trim().length
      facetPath += "|status:#{filter.status}"
    if filter.tag?.length
      sortedTags = _.sortBy(filter.tag.split(',')).join(',')
      facetPath += "|tags:#{sortedTags}"
    if filter.userId?
      facetPath += "|user:#{filter.userId}"
    return facetPath

  fromFacetString: (facetString) ->
    check facetString, String
    filter =
      queueName: ''
      search: ''
      status: ''
      tags: []
      userId: ''
    for f in facetString.split('|')
      f = f.split(':')
      if f[0] is 'tags' or f[0] is 'queueName'
        filter[f[0]] = f[1].split(',')
      else
        filter[f[0]] = f[1]
    return filter
 
  verifyFilterObject: (filter, userId) ->
    if not userId then return null
    check filter, Object
    f = filter
    if filter.userId and filter.userId is userId
      f.queueName = _.pluck Queues.find().fetch(), 'name'
    else if filter.queueName? and not Queues.findOne({name: filter.queueName, memberIds: userId})
      f.queueName = null
    else if not filter.queueName?
      f.userId = null
      f.queueName = _.pluck Queues.find({memberIds: userId}, {sort: {name: 1}}).fetch(), 'name'
    else
      f.userId = null
    if not (filter.status or filter.ticketNumber)
      #If no status filter and we're not looking at a specific ticket, default to 'not Closed' tickets.
      f.status = "!Closed"

    return f

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
  Facets.configure = (collection, configuration) ->
    check collection, Mongo.Collection

    #ready = false
    #refresh = (doc) ->
    #  if ready
    #    # Force regeneration of a facet whenever updated
    #    # See Focets.find adapter
    #    #Facets.remove
    #    console.log 'updating facets'
    #collection.find({}, {fields: _.mapObject(configuration, -> 1)}).observe
    #  added: refresh
    #  changed: (n, o) -> refresh _.union n, o
    #  removed: refresh
    #ready = true

    fields = _.keys configuration

    # TODO: split this so facet fields can be recomputed independent of each other
    collection.computeFacets = (selector) ->
      check selector, Object

      facets = {}
      _.each fields, (field) ->
        pipeline = []
        pipeline.push {$match: selector}
        if _.isArray configuration[field]
          pipeline.push {$unwind: "$#{field}"}
        pipeline.push {$group: {_id: "$#{field}", count: {$sum: 1}}}
        facets[field.replace(/\./g, '-')] = _.map collection.aggregate(pipeline), (s) ->
          {name: s._id, count: s.count}
      return facets

    # Adapt collection.find() so that finds from within publish functions automatically
    # regenerate facets when needed.
    unless collection._oldFind?
      collection._oldFind = collection.find
      collection.find = (selector) ->
        selector = selector || {}

        # TODO: find a way to only register this if called from within a publish function
        if true || @connection?
          stringify = Npm.require 'json-stable-stringify'
          facetString = stringify selector
          ready = false
          Facets.upsert {collection: collection._name, facetString: facetString},
            $set:
              facets: collection.computeFacets selector
          cursor = Facets.find {collection: collection._name, facetString: facetString}
          cursor.observe
            removed: (doc) ->
              Facets.upsert {collection: collection._name, facetString: doc.facetString},
                $set:
                  facets: collection.computeFacets selector
          ready = true
        return collection._oldFind.apply collection, arguments


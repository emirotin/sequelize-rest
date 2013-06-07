_ = require 'underscore'
_s = require 'underscore.string'
_.mixin _s.exports()

defaults =
  user: (req) -> req.user
  publicReadFields: ['createdAt', 'updatedAt', 'id']
  excludeSaveFields: ['createdAt', 'updatedAt', 'id']
  canRead: (user, idOrAll) -> true
  canReadPrivate: (user, idOrAll) -> false
  canWrite: (user, objOrNew) -> false
  canDelete: (user, obj) -> false

methodToAction =
  get: 'find'
  post: 'create'
  delete: 'delete'
  put: 'update'

error = (res, code, message) ->
  res.json code, error: message

ok = (res, data={}) ->
  res.json data

mergeConfig = (config, commonConfig) ->
  if not commonConfig
    return config
  res = {}
  for modelName, modelConfig of config
    if modelName == 'common'
      continue
    res[modelName] = modelConfig = _.extend {}, modelConfig
    for settingName, settingValue of commonConfig
      if modelConfig[settingName] == undefined
        modelConfig[settingName] = settingValue
      else if _.isArray modelConfig[settingName]
        modelConfig[settingName] = modelConfig[settingName].concat settingValue
  return res

module.exports = (sequelize, commonConfig) ->
  daos = sequelize.daoFactoryManager.daos
  commonConfig = _.extend {}, defaults, commonConfig
  getUser = commonConfig.user
  delete commonConfig.user

  models = {}
  modelConfigs = {}

  for model in daos
    models[model.name] = model

    modelConfigs[model.name] = modelConfig = _.pick model, ['canRead', 'canReadPrivate', 'canWrite', 'canDelete', 'beforeCreate']
    modelConfig.eagerLoad = model.eagerLoad?()
    modelConfig.publicReadFields = (name for name, attr of model.rawAttributes when attr.public)
    modelConfig.privateReadFields = (name for name, attr of model.rawAttributes when attr.private)
    modelConfig.excludeSaveFields = (name for name, attr of model.rawAttributes when attr.excludeSave)

  modelConfigs = mergeConfig modelConfigs, commonConfig

  return (req, res) ->
    # map HTTP method to readable name
    action = methodToAction[req.method.toLowerCase()]
    # get type name and id from url
    typeName = _(req.params.type).rtrim('s')
    id = req.params.id

    user = getUser req

    # shortcut
    if typeName == 'user' and id == 'current'
      return ok res, user
      #id = user?.id

    # get ORM model
    modelName = _(typeName).classify()
    model = models[modelName]

    # id is required for every operation except find (= findAll) and create
    if action not in ['find', 'create'] and not id
      return error res, 500, "ID not set for #{action} action"

    # except of shortcuts id must be numeric
    if id and not id.match /^\d+$/
      return error res, 500, "ID must be a number"

    # if id is defined convert it to Number
    if id
      id = Number(id)
      # safety check - POST with id trated as PUT
      if action == 'create'
        action = 'update'
    # if not id find is actually findAll
    else if action == 'find'
      action = 'findAll'

    # get params
    params = _.extend {}, if action in ['find', 'findAll'] then req.query else req.body[modelName]

    # generic error handler
    onError = (err) ->
      return error res, 500, err

    # do early permission checks
    modelConfig = modelsConfig[modelName] or {}
    switch action
      when 'find', 'findAll'
        if modelConfig.canRead and not modelConfig.canRead()
          return error res, 403, 'Read forbidden'
        canReadPrivate = not modelConfig.canReadPrivate or modelConfig.canReadPrivate(user, id or true)
        readFields = (modelConfig.publicReadFields or [])
        if canReadPrivate
          readFields = readFields.concat (modelConfig.privateReadFields or [])
      when 'create'
        if modelConfig.canWrite and not modelConfig.canWrite(user, true)
          return error res, 403, 'Write forbidden'

    modelMethod = switch action
      when 'update', 'delete', 'find' then 'find'
      when 'findAll' then 'findAll'
      when 'create' then 'create'

    queryParams = switch action
      when 'update', 'delete' then id
      when 'find' then where: id: id
      when 'create'
        if modelConfig.beforeCreate
          modelConfig.beforeCreate user, params
        params
      when 'findAll'
        searchParams = {}
        if '_order' of params
          searchParams.order = params._order
          delete params._order
        if '_page' of params
          searchParams.offset = (params._page - 1) * params._pageSize
          searchParams.limit = params._pageSize
          delete params._page
          delete params._pageSize
        if _(params).keys().length
          searchParams.where = params
        searchParams

    if action in ['find', 'findAll']
      if modelConfig.eagerLoad?.length
        queryParams.include = (models[m] for m in modelConfig.eagerLoad)

    # initiate query
    promise = model[modelMethod](queryParams)
    # handle any error
    promise.error onError

    # final actions
    switch action
      # simply return results
      when 'find', 'findAll', 'create'
        promise.success (results) ->
          # do we have restrictions?
          if readFields?.length
            # filter array
            if action == 'findAll'
              result = _.map results, (result) -> _.pick result, readFields
            # filter single object
            else
              result = _.pick results, readFields
          else
            # return what we got
            result = results
          # TODO: filter eager-loaded objects
          return ok res, result
      # make update query for found result
      when 'update'
        # do we have restrictions?
        if modelConfig.excludeSaveFields
          # filter params
          params = _.omit params, modelConfig.excludeSaveFields
        promise.success (result) ->
          if modelConfig.canWrite and not modelConfig.canWrite(user, result)
            return error res, 403, 'Write forbidden'
          result.updateAttributes(params)
            .success (result) ->
              if readFields?.length
                result = _.pick result, readFields
              return ok res, result
            .error onError
      # delete found result
      when 'delete'
        promise.success (result) ->
          if modelConfig.canDelete and not modelConfig.canDelete(user, result)
            return error res, 403, 'Delete forbidden'
          result.destroy()
            .success ->
              return ok res
            .error onError
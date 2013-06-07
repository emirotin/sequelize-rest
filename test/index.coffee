Sequelize = require 'sequelize'
sequelizeRest = require('../index')

sequelize = new Sequelize 'db', 'user', 'pwd',
  dialect: 'sqlite'

###
  common:
    publicReadFields: ['createdAt', 'updatedAt', 'id']
    excludeSaveFields: ['createdAt', 'updatedAt', 'id']
    canRead: (user, idOrAll) -> true
    canReadPrivate: (user, idOrAll) -> false
    canWrite: (user, objOrNew) -> false
    canDelete: (user, obj) -> false
  Project:
    publicReadFields: null

###

User = sequelize.define 'User', {
    firstName:
      type: Sequelize.STRING
      public: true
    lastName:
      type: Sequelize.STRING
      public: true
    displayName:
      type: Sequelize.STRING
      public: true
    email:
      type: Sequelize.STRING
      allowNull: true
      private: true
  }, {
    classMethods:
      canReadPrivate: (user, idOrAll) ->
        if idOrAll == true # bulk read
          return false
        return user?.id and user.id == idOrAll
      canWrite: (user, objOrNew) ->
        return user?.id and user.id == objOrNew?.id

  }

SocialAuth = sequelize.define 'SocialAuth',
  provider:
    type: Sequelize.STRING
  providerId:
    type: Sequelize.STRING
  displayName:
    type: Sequelize.STRING

SocialAuth.belongsTo User

Project = sequelize.define 'Project', {
    title:
      type: Sequelize.STRING
    intro:
      type: Sequelize.TEXT
    text:
      type: Sequelize.TEXT
  } , {
    classMethods:
      eagerLoad: -> ['User']
      canWrite: (user, objOrNew) ->
        if objOrNew == true
          return user?.id
        return user?.id and user.id == objOrNew?.UserId
      canDelete: (user, obj) ->
        return user?.id and user.id == obj?.UserId
      beforeCreate: (user, params) ->
        params.UserId = user.id
  }

Project.belongsTo User

console.log 111

sequelizeRest sequelize
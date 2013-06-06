module.exports = (sequelize) ->
  for model in sequelize.daoFactoryManager.daos
    console.log '====\n\n', model
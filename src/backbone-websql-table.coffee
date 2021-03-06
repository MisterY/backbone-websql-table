# Written as a Require.js module.

define ['underscore'], (_) ->
    class Guid
        constructor: ->

        # function for generating "random" id of objects in DB
        S4: ->
           return (((1+Math.random())*0x10000)|0).toString(16).substring(1);

        #function guid() {
        #   return (S4()+S4()+"-"+S4()+"-"+S4()+"-"+S4()+"-"+S4()+S4()+S4());
        #}
        # Generate a pseudo-GUID by concatenating random hexadecimals
        #  matching GUID version 4 and the standard variant.
        VERSION_VALUE = 0x4; # Bits to set
        VERSION_CLEAR = 0x0; # Bits to clear
        VARIANT_VALUE = 0x8; # Bits to set for Standard variant (10x)
        VARIANT_CLEAR = 0x3; # Bits to clear
        guid: ->
            data3_version = @S4()
            data3_version = (parseInt( data3_version.charAt( 0 ), 16 ) & VERSION_CLEAR | VERSION_VALUE).toString( 16 ) \
                + data3_version.substr( 1, 3 );
            data4_variant = @S4()
            data4_variant = data4_variant.substr( 0, 2 ) \
                + (parseInt( data4_variant.charAt( 2 ), 16 ) & VARIANT_CLEAR | VARIANT_VALUE).toString( 16 ) \
                + data4_variant.substr( 3, 1 );
            newGuid =  @S4() + @S4() + '-' + @S4() + '-' + data3_version + '-' + data4_variant + '-' + @S4() + @S4() + @S4()
            return newGuid

    class WebSqlTableStore
        tableName: ""
        debug: false

        #
        # static methods
        #

        @initialize = (model, options) ->
            # set sync
            if not model.store 
                store = new WebSqlTableStore(model, options)
                model.store = store
                model.sync = store.sync

        defaultOptions: {
            success: ->
                if @debug then console.log "default options, success"
            error: ->
                if @debug then console.log "default options, error"
            databaseName: "BackboneWebSqlDb"
            tableName: "DefaultTable"
            dbVersion: "1.0"
            dbSize: 1000000
            # Set debug to display debugging information in console.
            #debug: true
            debug: false
        }

        #
        # class methods
        #

        constructor: (@model, options) ->
            @model.store = @
            @model.sync = @sync

            # prepare options
            _.defaults(options, @defaultOptions)

            @debug = options.debug
            @setTableName(model, options)

            # get the real model
            actualModel = @getBackboneModelFor(model)
            @model = actualModel

            @db = @openDatabase(options)
            # create table if required
            @createTable(@model, @tableName)

        createTable: (model, tableName) ->
            if not model then console.error "Model not passed for store initialization!"
            if not tableName then throw { message: "tableName not passed to createTable." }
            #console.debug "create table"

            fields = @getFieldsFrom(model)
            # remove id field as we have to specify it as unique.
            _(fields).reject( (el) ->
                return el == "id" 
            )
            fieldsString = @getFieldsString fields

            success = (tx, resultSet) =>
                # check 'arguments' to see all arguments passed into the function.
                if @debug then console.log "table create success"
                #if options.success then options.success()
            
            error = (tx, error) ->
                window.console.error("Error while create table", error)

            sql = "CREATE TABLE IF NOT EXISTS '" + tableName + "' ('id' unique, " + fieldsString + ");"
            @_executeSql(sql, null, success, error)

        create: (model, success, error) ->
            # when you want use your id as identifier, use apiid attribute
            if not model.attributes[model.idAttribute]
                # Reference model.attributes.apiid for backward compatibility.
                obj = {};
                if model.attributes.apiid 
                    id = model.attributes.apiid 
                else 
                    guid = new Guid()
                    id = guid.guid()
                obj[model.idAttribute] = id
                model.set(obj);

            fields = @getFieldsFrom(model)
            fieldsString = @getFieldsString(fields)
            #valuesString = @getModelValuesString(model)
            values = @getModelAttributeValues(model)
            fieldsPlaceholder = @getFieldsPlaceholder(fields)
            sql = "INSERT INTO '" + model.store.tableName + "' (" + fieldsString + ") VALUES (" + fieldsPlaceholder + ");"
            #@_executeSql sql, [model.attributes[model.idAttribute], JSON.stringify(model.toJSON())], success, error
            @_executeSql sql, values, success, error

        delete: (model, success, error) ->
            # window.console.log("sql destroy");
            id = model.attributes[model.idAttribute] or model.attributes.id
            sql = "DELETE FROM '" + @tableName + "' WHERE (id=?);"
            @_executeSql sql,[model.attributes[model.idAttribute]], success, error

        getFieldsFrom: (model) ->
            if not model then throw { name: "InvalidArgumentException", message: "Model not passed to getFieldsFrom." }
            # create fields for every model attribute.
            fields = []
            for key of model.attributes
                #if key != "id" 
                fields.push key
                #console.log key
            #console.log fields
            return fields

        getFieldsString: (fields) ->
            # generate string
            fieldsString = ""
            for field, index in fields
                if index == 0
                    fieldsString += "'" + field + "'"
                else
                    fieldsString += ",'" + field + "'"
            #console.debug fieldsString

            return fieldsString

        getFieldsPlaceholder: (fields) ->
            # return "?, ?" string for Insert statement.
            result = ""
            for key, index in fields
                if index == 0
                    result += "?"
                else
                    #if key != 'id'
                    result += ",?"
            return result

        getBackboneModelFor: (obj) ->
            # Here we distinguish if we have a Collection or a Model.
            if obj instanceof Backbone.Collection
                model = new obj.model()
            if obj instanceof Backbone.Model
                model = obj
            return model

        getModelAttributeValues: (model) ->
            values = []
            for key of model.attributes
                #if key != "id" 
                values.push model.get(key)

            return values

        # not used
        getModelValuesString: (model) ->
            values = @getModelAttributeValues(model)

            # generate string
            valuesString = ""
            for value in values
                valuesString += ",'" + value + "'"

            return valuesString

        getUpdateFieldsAndValuesArray: (model) ->
            fields = @getFieldsFrom(model)
            values = @getModelAttributeValues(model)
            #sql = "UPDATE '" + @tableName + "' SET `value`=? WHERE(`id`=?);"
            #sql = "UPDATE '" + @tableName + "' SET '?'=? WHERE (id=?);"
            result = []

            for i in [0..fields.length - 1] by 1
                result.push fields[i]
                result.push values[i]
                
            return result

        find: (model, success, error) ->
            #window.console.log("sql find");
            id = model.attributes[model.idAttribute] || model.attributes.id
            sql = "SELECT * FROM '" + this.tableName + "' WHERE (id=?);"

            @_executeSql sql, [id], success, error

        findAll: (model, filter, success, error) ->
            # window.console.log("sql findAll");
            sql = "SELECT * FROM '" + this.tableName + "'"
            params = []

            if filter
                #
                sql += " WHERE ("
                for param of filter
                    sql += param
                    sql += "=?"
                    params.push filter[param]
                sql += ")"

            sql += ";"

            @_executeSql sql, params, success, error

        openDatabase: (options) ->
            if not @db 
                @databaseName = options.databaseName
                @db = window.openDatabase(@databaseName, options.dbVersion, @databaseName, options.dbSize);
            return @db

        _executeSql: (sql, params, success, error) ->
            onSuccess = (tx,result) ->
                #if WebSQLStore.debug {window.console.log(SQL, params, " - finished");}
                #if successCallback then successCallback(tx,result)
                if @debug then console.log "executeSql success"
                if success then success(tx, result)
            
            onError = (tx, err) ->
                #if WebSQLStore.debug 
                #    window.console.error(SQL, params, " - error: " + error)
                console.error err
                #if errorCallback then errorCallback(tx,error)
                if error then error(err)
            
            txSuccess = ->
                # console.log "tx success"
            txError = ->
                # console.log "tx error"

            @db.transaction (tx) =>
                if @debug then console.debug "running on", @databaseName, @tableName, ":", sql, "with params", params

                tx.executeSql(sql, params, onSuccess, onError)
            , txError, txSuccess

        setTableName: (model, options) ->
            # Set table name from model's type
            #if options.tableName
                # use pre-set table name. This works for collections.
                #tableName = options.tableName

            # if "model" is collection, get real model's type name
            if model instanceof Backbone.Collection
                tableName = model.model.name
            if model instanceof Backbone.Model
                # set table name to type name of the model.
                tableName = model.constructor.name
            # overwrite default table name.
            if tableName then options.tableName = tableName

            @tableName = tableName

        sync: (method, model, options) ->
            #console.log "sync:", method, model, options
            #console.log "sync"
            if not model.store then throw { message: "WebSql Table store not initialized for model." }
            store = model.store

            switch method
                when "read"
                    if @debug then console.log "sync: read"

                    onError = ->
                        console.error "find error"
                        if options.error then options.error()

                    if model instanceof Backbone.Collection
                        success = (tx, res) =>
                            if @debug then console.log "loaded collection"

                            len = res.rows.length
                            if len > 0 
                                result = [];

                                for i in [0..len - 1] by 1
                                    #result.push(JSON.parse(res.rows.item(i).value));
                                    result.push res.rows.item(i)

                            options.success(result)

                        store.findAll model, options.filter, success, onError

                    if model instanceof Backbone.Model
                        success = (tx, res) ->
                            if @debug then console.log "find success", res.rows.length
                            len = res.rows.length;
                            if len > 0
                                #result = JSON.parse(res.rows.item(0).value)
                                result = res.rows.item(0)
                            
                            options.success(result)
                        
                        store.find model, success, onError

                    #if model.attributes and model.attributes[model.idAttribute]
                        #store.find model, options.success, options.error
                    #else
                        #store.findAll model, options.success, options.error

                when "create"
                    if @debug then console.log "sync: create"
                    store.create model, options.success, options.error

                when "update"
                    if @debug then console.log "sync: update"
                    store.update model, options.success, options.error

                when "delete"
                    if @debug then console.log "sync: delete"
                    store.delete model, options.success, options.error

        update: (model, success, error) ->
            #console.error "not implemented"
            if @debug then console.log "updating model", model.get('id')

            id = model.attributes[model.idAttribute] or model.attributes.id

            #sql = "UPDATE '" + @tableName + "' SET `value`=? WHERE(`id`=?);"
            #fieldsAndValues = @getUpdateFieldsAndValuesArray(model)
            #fieldsAndValues.push model.get('id')
            #sql = "UPDATE '" + @tableName + "' SET ?=? WHERE (id=?);"
            sql = "UPDATE '" + @tableName + "' SET "

            fields = @getFieldsFrom(model)
            for i in [0..fields.length - 1] by 1
                if i != 0 then sql += ", "
                sql += fields[i]
                sql += "=?"
            sql += " WHERE (id=?)"

            values = @getModelAttributeValues(model)
            values.push model.get('id')

            #@_executeSql sql,[JSON.stringify(model.toJSON()), model.attributes[model.idAttribute]], success, error
            @_executeSql sql, values, success, error
    
    return WebSqlTableStore
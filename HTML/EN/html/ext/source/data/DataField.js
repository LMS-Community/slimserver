/*
 * Ext JS Library 2.2.1
 * Copyright(c) 2006-2009, Ext JS, LLC.
 * licensing@extjs.com
 * 
 * http://extjs.com/license
 */

/**
 * @class Ext.data.Field
 * <p>This class encpasulates the field definition information specified in the field definition objects
 * passed to {@link Ext.data.Record#create}.</p>
 * <p>Developers do not need to instantiate this class. Instances are created by {@link Ext.data.Record.create}
 * and cached in the {@link Ext.data.Record#fields fields} property of the created Record constructor's <b>prototype.</b></p>
*/
Ext.data.Field = function(config){
    if(typeof config == "string"){
        config = {name: config};
    }
    Ext.apply(this, config);
    
    if(!this.type){
        this.type = "auto";
    }
    
    var st = Ext.data.SortTypes;
    // named sortTypes are supported, here we look them up
    if(typeof this.sortType == "string"){
        this.sortType = st[this.sortType];
    }
    
    // set default sortType for strings and dates
    if(!this.sortType){
        switch(this.type){
            case "string":
                this.sortType = st.asUCString;
                break;
            case "date":
                this.sortType = st.asDate;
                break;
            default:
                this.sortType = st.none;
        }
    }

    // define once
    var stripRe = /[\$,%]/g;

    // prebuilt conversion function for this field, instead of
    // switching every time we're reading a value
    if(!this.convert){
        var cv, dateFormat = this.dateFormat;
        switch(this.type){
            case "":
            case "auto":
            case undefined:
                cv = function(v){ return v; };
                break;
            case "string":
                cv = function(v){ return (v === undefined || v === null) ? '' : String(v); };
                break;
            case "int":
                cv = function(v){
                    return v !== undefined && v !== null && v !== '' ?
                           parseInt(String(v).replace(stripRe, ""), 10) : '';
                    };
                break;
            case "float":
                cv = function(v){
                    return v !== undefined && v !== null && v !== '' ?
                           parseFloat(String(v).replace(stripRe, ""), 10) : ''; 
                    };
                break;
            case "bool":
            case "boolean":
                cv = function(v){ return v === true || v === "true" || v == 1; };
                break;
            case "date":
                cv = function(v){
                    if(!v){
                        return '';
                    }
                    if(Ext.isDate(v)){
                        return v;
                    }
                    if(dateFormat){
                        if(dateFormat == "timestamp"){
                            return new Date(v*1000);
                        }
                        if(dateFormat == "time"){
                            return new Date(parseInt(v, 10));
                        }
                        return Date.parseDate(v, dateFormat);
                    }
                    var parsed = Date.parse(v);
                    return parsed ? new Date(parsed) : null;
                };
             break;
            
        }
        this.convert = cv;
    }
};

Ext.data.Field.prototype = {
    /**
     * @cfg {String} name
     * The name by which the field is referenced within the Record. This is referenced by,
     * for example, the <em>dataIndex</em> property in column definition objects passed to {@link Ext.grid.ColumnModel}
     */
    /**
     * @cfg {String} type
     * (Optional) The data type for conversion to displayable value. Possible values are
     * <ul><li>auto (Default, implies no conversion)</li>
     * <li>string</li>
     * <li>int</li>
     * <li>float</li>
     * <li>boolean</li>
     * <li>date</li></ul>
     */
    /**
     * @cfg {Function} convert
     * (Optional) A function which converts the value provided by the Reader into an object that will be stored
     * in the Record. It is passed the following parameters:<ul>
     * <li><b>v</b> : Mixed<div class="sub-desc">The data value as read by the Reader.</div></li>
     * <li><b>rec</b> : Mixed<div class="sub-desc">The data object containing the row as read by the Reader.
     * Depending on Reader type, this could be an Array, an object, or an XML element.</div></li>
     * </ul>
     */
    /**
     * @cfg {String} dateFormat
     * (Optional) A format string for the {@link Date#parseDate Date.parseDate} function, or "timestamp" if the
     * value provided by the Reader is a UNIX timestamp, or "time" if the value provided by the Reader is a 
     * javascript millisecond timestamp.
     */
    dateFormat: null,
    /**
     * @cfg {Mixed} defaultValue
     * (Optional) The default value used <b>when a Record is being created by a
     * {@link Ext.data.Reader Reader}</b> when the item referenced by the <b><tt>mapping</tt></b> does not exist in the data object
     * (i.e. undefined). (defaults to "")
     */
    defaultValue: "",
    /**
     * @cfg {String} mapping
     * (Optional) A path specification for use by the {@link Ext.data.Reader} implementation
     * that is creating the Record to access the data value from the data object. If an {@link Ext.data.JsonReader}
     * is being used, then this is a string containing the javascript expression to reference the data relative to
     * the Record item's root. If an {@link Ext.data.XmlReader} is being used, this is an {@link Ext.DomQuery} path
     * to the data item relative to the Record element. If the mapping expression is the same as the field name,
     * this may be omitted.
     */
    mapping: null,
    /**
     * @cfg {Function} sortType
     * (Optional) A function which converts a Field's value to a comparable value in order to ensure correct
     * sort ordering. Predefined functions are provided in {@link Ext.data.SortTypes}
     */
    sortType : null,
    /**
     * @cfg {String} sortDir
     * (Optional) Initial direction to sort. "ASC" or "DESC"
     */
    sortDir : "ASC"
};
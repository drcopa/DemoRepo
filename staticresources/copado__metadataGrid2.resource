function setWithoutRebinding(list, newList) {
    list.splice(0, list.length); // clear the array, without re-binding it.
    // NR: add elements in chunks, to avoid stack trace limits
    while(newList.length)
        Array.prototype.push.apply(list, newList.splice(0,10000));
}

function MetadataGrid2(conf) {
    this._initGrid(conf);
    // Save the HTML for use in resetGrid
    this._initialHTML = this.eltMain.html();
}

MetadataGrid2.prototype._initGrid = function(conf) {
    this.conf = conf;

    this.conf.gridMode = this.conf.gridMode || "orgMetadata"; // grid mode affects the behavior of the loading, rendering columns, and saving.
    this.isMetadataGrid = this.conf.gridMode === 'orgMetadata';

    console.debug('_initGrid()', this.conf.gridMode, this.isMetadataGrid);
    console.assert(this.conf.data.orgId, "MetadataGrid2.init: config had no orgId");

    this.allMetaData = [];
    this.selectedMetadata = []; // selected items, referencing this.allMetaData
    this.allMetaData_cachedDate = "";

    //this.conf.isScalable = false; // true for having the filter INSIDE the grid, not as a combobox 
    this.isTypeFilterable = (this.conf.isScalable); // true for having the filter INSIDE the grid, not as a combobox 
    console.debug("MetadataGrid2() conf.isScalable", this.conf.isScalable);

    this.TypeFilterType = 'checkedlist';
    this.filterByType = ''; // null means: no filter selected
    this.filterByTypeList = [];
    this.filterByTypeSelectedIndex = 0;
    this.savedFilters = null;

    this.isRendered = false;
    this.eltGrid = null;
    this.eltMetaDataTypeFilter = null;
    this.eltTabs = null;

    this.conf.eltMainId = this.conf.eltMainId || 'metadataGrid2'; // overridable main ID
    this.eltMain = $copado('#'+this.conf.eltMainId);
    console.assert(this.eltMain.length);

    if(this.conf.isScalable)
        this.eltMain.find('.mg2_scaleFilterFrame').show();
    else
        this.eltMain.find('.mg2_scaleFilterFrame').hide();

    if(this.conf.gridMode==='Translations') {
        // translations are never filterable by type. They will be manually filtered later
        this.isTypeFilterable = false;
        this.filterByType = 'Translations';
        this.eltMain.find('.mg2_scaleFilterFrame').hide();
    }

};

// Resets the grid
MetadataGrid2.prototype.resetGrid = function(conf) {
    console.debug("MetadataGrid2.resetGrid()");
    this.eltMain.html(this._initialHTML);
    this._initGrid(conf);
};

// selects/deselects a bunch of elements.
MetadataGrid2.prototype._setSelectionState = function(selected, elts, calledFromSelectAll, rowdata) {
    console.debug("MetadataGrid2._setSelectionState", selected, elts.length);

    // NR: we need to translate the elts list to the real elts for (un)selectAll
    var i, e, t, idx_allItems = null;
    if(calledFromSelectAll) {
        idx_allItems = {};
        for(i=0 ; i < this.allMetaData.length ; i++ ) {
            e = this.allMetaData[i];
            idx_allItems[e.t+' '+e.n] = e;
        }
    }

    // locate each elt in the 
    for(i=0 ; i < elts.length ; i++) {
        e = elts[i];
        if(idx_allItems) {
            e =  idx_allItems[elts[i].t+' '+elts[i].n];
            if(!e)
                continue; // the element selected might not be in allMetaData, just ignore it.
        }
        e.s = selected;
        var existsInSelected = this.selectedMetadata.indexOf(e);
        if(selected && existsInSelected===-1) {
            this.selectedMetadata.push(e);
        }else if(!selected && existsInSelected>-1) {
            this.selectedMetadata.splice(existsInSelected,1);
        }
        // little hack to allow actually clicking on "r" and setting s, and saving
        if( this.conf.gridMode === 'gitCommit') {
            if(rowdata)
                e.r = rowdata.r;
            if(calledFromSelectAll && !selected)
                e.r = false;
        }
    }

    // visual feedback, flashing the tab
    var elt = this.eltMain.find('.mg2_tabs li').get(1);
    elt.style.animation = '';
    setTimeout(function() {
        elt.style.animation = 'flash 2s 1';
    }, 5);

    // fire a custom event telling the selection changed.
    var event = new CustomEvent("copadoMetadataGrid2Changed", { detail: { metadataGrid2: this } });
    document.dispatchEvent(event);
};

// forces filtering by the type currently selected
MetadataGrid2.prototype._setGridFiltersByType = function() {
    var that = this;
    var isTranslationsMode = this.conf.gridMode==='Translations';
    if(this.isTypeFilterable || isTranslationsMode) {
        if(isTranslationsMode) {
            that.filterByType = 'Translations';
            console.debug("_setGridFiltersByType() translations");
        }
        that.eltGrid.jqxGrid('removefilter', 't');
        var group = new $copado.jqx.filter();
        var filter = group.createfilter('stringfilter', that.filterByType, 'contains');
        group.addfilter(0, filter);
        that.eltGrid.jqxGrid('addfilter', 't', group);
        that.eltGrid.jqxGrid('applyfilters');
    }
};

MetadataGrid2.prototype._reapplyFilters = function(tabIndex) {
    var that = this;
    if(tabIndex===undefined && this.eltTabs)
        tabIndex = this.eltTabs.jqxTabs('selectedItem');

    //console.debug('_reapplyFilters()', tabIndex, that.savedFilters);
    if(tabIndex === 0) {
        // Filter by TYPE
        that.eltGrid.jqxGrid('setcolumnproperty', 's', 'filterable', true);
        that.eltGrid.jqxGrid('removefilter', 's');
        that.eltGrid.jqxGrid('applyfilters');
        if(that.savedFilters)
            that.eltGrid.jqxGrid('loadstate', that.savedFilters);
        that._setGridFiltersByType();
    }else if(tabIndex === 1) {
        that.savedFilters = that.eltGrid.jqxGrid('getstate');
        // Filter by SELECTION, regardless of the type
        that.eltGrid.jqxGrid('clearfilters');
        that.eltGrid.jqxGrid('setcolumnproperty', 's', 'filterable', false);
        that.eltGrid.jqxGrid('addfilter', 's', that.jqxFilterBySelection);
        that.eltGrid.jqxGrid('applyfilters');
    }else{
        console.warn("uknown tab!");
    }
};

MetadataGrid2.prototype._getColumnsByGridMode = function() {
    var type = this.conf.gridMode;
    var columns;

    if (type == 'metadataselector') {
        columns = [{
                text: copadoLabels.selected,
                columntype: 'checkbox',
                filtertype: 'bool',
                datafield: 's',
                width: 60
            },
            {
                text: copadoLabels.name,
                filtertype: 'textbox',
                filtercondition: 'contains',
                editable: false,
                datafield: 'n',
                width: 400
            },
            {
                text: copadoLabels.type,
                datafield: 't',
                filterable: !this.isTypeFilterable,
                filtertype: this.TypeFilterType,
                editable: false,
                columntype: 'textbox'
            },
            {
                text: copadoLabels.LASTMODIFIEDBY,
                filtertype: 'textbox',
                editable: false,
                datafield: 'b',
                width: 220
            },
            {
                text: copadoLabels.LastModifiedDate,
                filtertype: 'textbox',
                editable: false,
                datafield: 'd',
                width: 120
            },
            {
                text: copadoLabels.CREATEDBY,
                filtertype: 'textbox',
                editable: false,
                datafield: 'cb',
                width: 220
            },
            {
                text: copadoLabels.CREATEDDATE,
                filtertype: 'textbox',
                editable: false,
                datafield: 'cd',
                width: 120
            }
        ];

    } else if(type === 'orgMetadata') {
        columns = [
            {text: copadoLabels.name, filtertype: 'textbox', filtercondition: 'contains', editable:false, datafield: 'n'},
            {text: copadoLabels.type, datafield: 't', filterable: !this.isTypeFilterable, filtertype:this.TypeFilterType, editable:false ,  columntype: 'textbox',width: 160},
            {text: copadoLabels.LastModifiedById, filtertype: 'textbox', editable:false, datafield: 'b', width: 120},
            {text: copadoLabels.LastModifiedDate, filtertype: 'textbox', editable:false, datafield: 'd', width: 120},
            {text: copadoLabels.CREATEDBY, filtertype: 'textbox', editable:false, datafield: 'cb', width: 220},
            {text: copadoLabels.CREATEDDATE, filtertype: 'textbox', editable:false, datafield: 'cd', width: 120}
        ];
    } else if(type === 'gitCommit') {
        columns = [{
            text: copadoLabels.selected,
            columntype: 'checkbox',
            filtertype: 'bool',
            datafield: 's',
            width: 60
        }, {text: copadoLabels.RETRIEVE_ONLY, columntype: 'checkbox', filterable: false, datafield: 'r', width: 85 }, {
            text: copadoLabels.name,
            filtertype: 'textbox',
            filtercondition: 'contains',
            editable: false,
            datafield: 'n',
            width: '30%'
        }, {
            text: copadoLabels.type,
            datafield: 't',
            filtertype: this.TypeFilterType,
            filterable: !this.isTypeFilterable,
            editable: false,
            columntype: 'textbox',
            width: '10%'
        }, {
            text: copadoLabels.LastModifiedById,
            filtertype: 'textbox',
            filtercondition: 'contains',
            editable: false,
            datafield: 'b',
            width: 220
        }, {
            text: copadoLabels.LastModifiedDate,
            filtertype: 'textbox',
            filtercondition: 'contains',
            editable: false,
            datafield: 'd',
            width: 120
        },
            {text: copadoLabels.CREATEDBY, filtertype: 'textbox', editable:false, datafield:'cb', width:220},
            {text: copadoLabels.CREATEDDATE, filtertype: 'textbox', editable:false, datafield:'cd', width:120}
        ];
    } else {
        columns = [{
            text: copadoLabels.selected,
            columntype: 'checkbox',
            filtertype: 'bool',
            datafield: 's',
            width: 60
        }, {
            text: copadoLabels.name,
            filtertype: 'textbox',
            filtercondition: 'contains',
            editable: false,
            datafield: 'n',
            width: '30%'
        }, {
            text: copadoLabels.type,
            datafield: 't',
            filtertype: this.TypeFilterType,
            filterable: !this.isTypeFilterable,
            editable: false,
            columntype: 'textbox',
            width: '10%'
        }, {
            text: copadoLabels.LastModifiedById,
            filtertype: 'textbox',
            filtercondition: 'contains',
            editable: false,
            datafield: 'b',
            width: 220
        }, {
            text: copadoLabels.LastModifiedDate,
            filtertype: 'textbox',
            filtercondition: 'contains',
            editable: false,
            datafield: 'd',
            width: 120
        },
            {text: copadoLabels.CREATEDBY, filtertype: 'textbox', editable:false, datafield:'cb', width:220},
            {text: copadoLabels.CREATEDDATE, filtertype: 'textbox', editable:false, datafield:'cd', width:120}
        ];
    }
    return columns;
};

// (re) renders the grid
MetadataGrid2.prototype.render = function(cbAfterRender) {
    var that = this;

    if(this.isRendered) {
        // Just refresh and return, never re-render
        console.debug('MetadataGrid2.render() re-rendering', this.filterByType);
        this._reapplyFilters();
        this.eltGrid.jqxGrid('updatebounddata', 'filter');
        if(cbAfterRender)
            cbAfterRender();
        return;
    }
    this.isRendered = true;
    console.debug('MetadataGrid2.render() rendering');

    // rendering the "tabs", which in fact are a filter type
    this.eltTabs = this.eltMain.find('.mg2_tabs');

    if(this.eltTabs.length) {
        this.eltTabs.jqxTabs({});

        this.jqxFilterBySelection = new $copado.jqx.filter();
        this.jqxFilterBySelection.addfilter(1, this.jqxFilterBySelection.createfilter('booleanfilter', true, 'EQUAL'));

        this.eltTabs.on('selected', function (event) {
            if(!event.args)
                return;
            that._reapplyFilters(event.args.item);
        });
    }else{
        this.eltTabs = null;
    }

    // rendering the metadata type filter and binding its actions
    if(this.isTypeFilterable) {

        this.eltMetaDataTypeFilter = this.eltMain.find('.mg2_scaleFilter');

        this.eltMetaDataTypeFilter.jqxComboBox({
            source: this.filterByTypeList,
            selectedIndex: 0,
            width: '300px',
            height: '30px'
        });
        this.eltMetaDataTypeFilter.bind('select', function(event) {
            var args = event.args;
            if (args) {
                that.filterByTypeSelectedIndex = args.index;
                that.filterByType = that.filterByTypeList[that.filterByTypeSelectedIndex];
            }
        });
        this.eltMetaDataTypeFilter.bind('close', function(event) {
            console.debug('MetadataGrid2: filter loading', that.filterByType);
            if(!that.filterByType)
                return;

            document.body.focus();
            that.eltMetaDataTypeFilter.jqxComboBox({ disabled: true }); 
            
            // detach the slow process.
            window.setTimeout(function() {
                lockScreen();
                // even if loadmetadata is never called, this will ensure the combo is enabled.
                that.eltMetaDataTypeFilter.jqxComboBox({ disabled: false });
                that.loadMetaData(function(error) {
                    console.debug('MetadataGrid2: filter done');
                    that.render();
                    unlockScreen();
                    that.eltMetaDataTypeFilter.jqxComboBox({ disabled: false });

                    // fire a custom event telling the selection changed.
                    var event = new CustomEvent("copadoMetadataGrid2TypeChanged", { detail: { metadataGrid2: this } });
                    document.dispatchEvent(event);
                });
            },500);
        });
    }

    // now, finally, render the grid (must be done last!)
    var theme = 'base';
    var source = {
        localdata: this.allMetaData,
        datafields: [
            { name: 's', type: 'bool' },
            { name: 'r', type: 'bool' },
            { name: 't', type: 'string' },
            { name: 'n', type: 'string' },
            { name: 'b', type: 'string' },
            { name: 'd', type: 'string' },
            { name: 'cb', type: 'string' },
            { name: 'cd', type: 'string' }
        ],
        datatype: 'array',
        updaterow: function (rowid, rowdata, commit) {
            try{
                if(commit)
                    commit(true);
                else
                    console.warn("no commit fn defined");
                that._setSelectionState(rowdata.s, [that.allMetaData[rowid]], false, rowdata);
            }catch(e) {
                console.error(e);
            }
        }
    };

    //adapter wrapper
    var dataAdapter = new $copado.jqx.dataAdapter(source);
    
    //keep jquery pointer for performance query
    this.eltGrid = this.eltMain.find('.mg2_jqxgrid');
    console.assert(this.eltGrid.length);
    
    //save local source
    this.datasource = source;
    
    this.eltGrid.jqxGrid({
        width: '100%',
        height: '300px',
        source: dataAdapter,
        showfilterrow: true,
        filterable: true,
        theme: theme,
        editable: true, 
        selectionmode: 'none',
        enablebrowserselection: true,
        pageable: true,
        pagesizeoptions: ['10', '50','100','500','1000','5000'],
        pagesize: 200,
        sortable: true,
        columnsresize: true,
        localization: localizationobj,
        columns: this._getColumnsByGridMode(),
        ready: function(){
            console.log('MetadataGrid2.render() ready grid event');
            try{
                if(that.hasPreviousSelected)
                    that.addSelectedFilter(that.eltGrid);
                cbAfterRender(that);
                //that.eltGrid.jqxGrid('sortby','d', false, null, false);
            }catch(e) { console.error(e); }
        }
    });

    if(this.conf.gridMode === 'gitCommit') {
        
        this.eltGrid.on('cellvaluechanged', function (event) {            
            // hack: if the col clicked is r, check the selection as well
            var t = that.eltGrid.jqxGrid('getrowdata', event.args.rowindex);
            
            if (event.args.datafield=='r' && t.r === true && t.s === false) {
                that.eltGrid.jqxGrid('setcellvalue', event.args.rowindex, "s", true);
                that.eltGrid.jqxGrid('setcellvalue', event.args.rowindex, "r", true);
            }
            else if(event.args.datafield=='r' && t.r === false && t.s === true) {
                that.eltGrid.jqxGrid('setcellvalue', event.args.rowindex, "r", false);
            }
            else if (event.args.datafield=='s' && t.r === true && t.s === false) {
               that.eltGrid.jqxGrid('setcellvalue', event.args.rowindex, "r", false);
               that.eltGrid.jqxGrid('setcellvalue', event.args.rowindex, "s", false);
            }
            //that.eltGrid.jqxGrid('refreshdata');
            //that.eltGrid.jqxGrid('applyfilters');
            that._setSelectionState(t.s, [t], true, t);
        });
    }

    if(this.conf.gridMode !== 'orgMetadata') {
        var selectAll = function(sel) {
                var list = that.eltGrid.jqxGrid('getrows');
                that._setSelectionState(sel, list, true);
                that.render();
        };
        // Initialize the select all/unselect all buttons
        var $unselectAll = $copado('<button>Unselect All</button>').on('click', function(e) {
                e.preventDefault();
                selectAll(false);
            });

        var $selectAll = $copado('<button>Select All</button>').on('click', function(e) {
            e.preventDefault();
            selectAll(true);
        });
        this.eltMain.find('.jqx-grid-pager > div')
            .prepend($unselectAll)
            .prepend($selectAll);
    }
};

MetadataGrid2.prototype._createCacheDeleteButton = function(){
    var $btn = $copado('[id$=removeCache]');
    this._createCacheDeleteButtonText = this._createCacheDeleteButtonText || $copado('[id$=removeCache]').html() || '';
    var text = this._createCacheDeleteButtonText;
    if (!this.allMetaData_cachedDate) {
        $copado('[id*=removeCacheContainer]').hide();
    } else {
        $copado('[id*=removeCacheContainer]').show();
        text = this._createCacheDeleteButtonText.replace('__DATE__', this.allMetaData_cachedDate);
        $btn.html( text );
    }
    if (this.filterByType) {
        text = text.replace('__METATYPE__', 'for ' + this.filterByType||'');
        $btn.html( text );
    } else {
        text = text.replace('__METATYPE__', '');
        $btn.html( text );
    }

    $btn.show();
};

MetadataGrid2.prototype.loadMetaDataTypes = function(callbackFinished, forceReloading) {
    var that = this;
    console.debug('loadMetaDataTypes() calling forceReloading=', forceReloading);

    // never reload the metadata types
    if(this.filterByTypeList.length &&!forceReloading) {
        if(callbackFinished)
            callbackFinished(event);
        return;
    }

    JsRemoting.metaData.getList(
        this.conf.data.orgId,
        this.conf.ns,
        function(result) {
            console.debug('MetadataGrid2.loadMetaDataTypes()', result.length);
            if(!result || !result.length)
                alert('Could not load metadata types from the server');
            setWithoutRebinding(that.filterByTypeList, result);

            // TODO: this shouldnt be here, since it's UI
            if(that.isTypeFilterable) {
                that.eltMetaDataTypeFilter.jqxComboBox('source', that.filterByTypeList);
            }

            if(callbackFinished)
                callbackFinished();
        },
        function(event) {
            console.error('loadMetaDataTypes()', event);
            alert('Exception: ' + event.message);
            if(callbackFinished)
                callbackFinished(event);
        },
        function(event) {
            console.error('loadMetaDataTypes() #2', event);
            alert('Exception: ' + event.message);
            if(callbackFinished)
                callbackFinished(event);
        }
    );
};

MetadataGrid2.prototype.loadSelectedMetaData = function(callbackFinished) {
    var selectedMetadata = dw.u.getSavedData(this.conf.data.id, this.conf.attachmentName);
    console.debug('MetadataGrid2.loadSelectedMetaData()', selectedMetadata?selectedMetadata.length:selectedMetadata);
    if( selectedMetadata === false ) {
        setWithoutRebinding(this.selectedMetadata, []);
        if(callbackFinished)
            callbackFinished();
        return;
    }
    setWithoutRebinding(this.selectedMetadata, selectedMetadata);
    if(callbackFinished)
        callbackFinished();
};

// (re) loads only the metadata, possibly filtered
MetadataGrid2.prototype.loadMetaData = function(callbackFinished, forceRefresh) {
    var that = this;
    var conf = this.conf;

    if(this.isTypeFilterable && !this.filterByType) {
        console.debug('MetadataGrid2.loadMetaData: not loading metadata');
        that._setGridData([]); // set the data, even if it is emptyish.
        if(callbackFinished)
            callbackFinished();
        return;
    }

    var url = conf.server.metadataUrl.replace(new RegExp('__ORGID__', 'g'), conf.data.orgId);
    url = this.filterByType ? url + '&type=' + (this.filterByType||'') + '&scalable=true' : url;
    if(this.conf.gridMode==='Users') {
        url = this.conf.users_url;
    }else if(this.conf.gridMode==='metadataselector' && window.rock !== undefined) {
        url = rock.config.metadata_url;
    }
    console.debug('MetadataGrid2.loadMetaData', "force?"+forceRefresh, conf.data.orgId, this.filterByType, url);

    dw.u.getCachedRemote({
       url: url,
       name: this.filterByType || conf.attachmentName,
       parentId: conf.data.orgId,
       force: forceRefresh,
       synchronous: false,
       success: function(allMetaData, cachedDate){
            console.debug('MetadataGrid2.loadMetaData done', '#'+allMetaData.length, cachedDate, that.selectedMetadata.length, that.filterByType);
            that._setGridData(allMetaData);

            that.allMetaData_cachedDate  = cachedDate;
            that._createCacheDeleteButton();

            // refresh the grid/filter, so the column type has filter values
            if(!this.isTypeFilterable)
                that.eltGrid.jqxGrid('updatebounddata');
            
            if(callbackFinished)
                callbackFinished();
       },
       error: function(r){
           console.error('MetadataGrid2.Error: ',r);
            if(callbackFinished)
                callbackFinished(r);
       }
    });
};

// (re) loads all the data of the grid, does not render.
MetadataGrid2.prototype.loadData = function(callbackFinished) {
    var that = this;
    console.debug('MetadataGrid2.loadData() isTypeFilterable=', that.isTypeFilterable);
    this.loadSelectedMetaData(function(err) {
        if(err) {
            console.error('MetadataGrid2.loadData() error=', err);
            alert(err);
            return;
        }
        if(that.isTypeFilterable) {
            that.loadMetaDataTypes();
            that.loadMetaData(callbackFinished);
        }else{
            that.loadMetaData(callbackFinished);
        }
    });
};

// calls the API to refresh the metadata attachment (filtered or not)
MetadataGrid2.prototype.refreshCache = function(callbackFinished) {
    var that = this;
    lockScreen();
    this.loadMetaData(function() {
        console.info("MetadataGrid2.refreshCache() grid data refreshed");
        that.render();
        unlockScreen();
        if(callbackFinished)
            callbackFinished();
    }, true);
 };

// changes the grid data, replacing whatever is in there now.
MetadataGrid2.prototype._matchSelectedItemsWithAllMetaData = function(allMetaData) {
    var i, e, t, idx_allItems = {};

    // create a quick index of all the metadata items.
    for(i=0 ; i < allMetaData.length ; i++ ) {
        e = allMetaData[i];
        e.s = e.s || false;
        idx_allItems[e.t+' '+e.n] = e;
    }

    if( this.conf.gridMode === 'gitCommit') {
        for(i=0 ; i < allMetaData.length ; i++ ) {
            e = allMetaData[i];
            e.r = e.r || false;
        }
    }

    // now, try to find the selected items. If not found, add them to the allMetaData array.
    // the grid will filter those if needed.
    for(i=0 ; i < this.selectedMetadata.length ; i++ ) {
        e = this.selectedMetadata[i];
        e.s = true;
        t = idx_allItems[e.t+' '+e.n];
        if( t ) {
            t.s = true;
        }else{
            allMetaData.push(e);
        }
    }
};

// changes the grid data, replacing whatever is in there now.
MetadataGrid2.prototype._setGridData = function(allMetaData) {
    this._matchSelectedItemsWithAllMetaData(allMetaData);

    if( this.conf.gridMode === 'gitCommit') {
        // save all the .r selections, rebind the data, and restore them in the new dataset.
        var e, eltsWithRetrieveOnly = [];
        for(i=0 ; i < this.selectedMetadata.length ; i++ ) {
            e = this.selectedMetadata[i];
            if(e.r)
                eltsWithRetrieveOnly.push(e.t+' '+e.n);
        }
        setWithoutRebinding(this.allMetaData, allMetaData);

        idx_allItems = {};
        for(i=0 ; i < this.allMetaData.length ; i++ ) {
            e = this.allMetaData[i];
            if( eltsWithRetrieveOnly.indexOf(e.t+' '+e.n)>-1) {
                e.r = true;
            }
        }
    }else{
        setWithoutRebinding(this.allMetaData, allMetaData);
    }

    console.debug("MetadataGrid2._setGridData() all=", this.allMetaData.length, 'sel=',this.selectedMetadata.length);
};

// fetches the selected data again. Useful for the "cancel" action
MetadataGrid2.prototype.reloadSelections = function() {
    var that = this;
    lockScreen();
    that.loadSelectedMetaData(function() {
        that._matchSelectedItemsWithAllMetaData(that.allMetaData);
        // NR: workaround because the selection show all the data, for some reason.
        if(that.eltTabs)
            that.eltTabs.jqxTabs('select', 0);
        that.render();
        unlockScreen();
    });
};

MetadataGrid2.prototype.refreshMetadataTypes = function() {
    var that = this;
    lockScreen();
    $copado('[id*=removeMTCache]').hide();
    dw.u.deleteAttach(that.conf.data.orgId,'MetadataTypes');
    that.loadMetaDataTypes(function() {
        unlockScreen();
    }, true);
    return false;
}
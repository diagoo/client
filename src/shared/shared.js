const _ = require('lodash')


/* ===== Database ===== */

function saveModel(db, model) {
  var data = nodesToRows(model.nodes)

  db.allDocs({
    include_docs: true
  }).then(function (result) {

    var dataDb = result.rows.map(function(r) {
      return r.doc
    })

    var diff =
      _.differenceWith(data, dataDb, _.isEqual)

    console.log(data, dataDb, diff)

    db.bulkDocs(diff)
      .then(function (result) {
        console.log('saved', result)
      }).catch(function(err) {
          console.log(err)
      })

  }).catch(function (err) {
    console.log(err)
  })
}

function loadModel(db, callback) {
  db.allDocs({
    include_docs: true
  }).then(function (result) {
    callback(rowsToNodes(result.rows))
  }).catch(function (err) {
    console.log(err)
  })
}

function rowsToNodes(rows) {
  return rows.reduce(function(map, obj) {
    map[obj.doc._id] =  
      { content: obj.doc.content
      , children: obj.doc.children
      , rev: obj.doc._rev
      , deleted: obj.doc._deleted ? true : false
      }
    return map
  }, {})
}

function nodesToRows(nodes) {
  var rows = Object.keys(nodes).map(function(key) {
    return  { "_id": key
            , "_rev": nodes[key].rev
            , "content": nodes[key].content
            , "children": nodes[key].children 
            }
  })

  return rows
}

function onChange(change) {
  var db = this.db
  if(change.deleted) {
    gingko.ports.externals.send(['change-deleted', change.id])
  }
  else if (change.doc._conflicts) {
    db.get(change.id, {
      open_revs: change.doc._conflicts
    })
    .then(function(responses) {
      var docs = responses
        .filter(function(response){
          return 'ok' in response
        })
        .map(function(response) {
          return response.ok
        })
        .concat(change.doc)

      var wDocs = JSON.parse(JSON.stringify(docs))

      var winning = wDocs.reduce(function(winning, doc) {
        return winning && resolver(doc, winning)
      }, wDocs.pop())

      if (!winning) throw({
        error: 'conflict_resolution_failed',
        reason: 'The conflict could not be resolved, resolveFun did not return a doc'
      })

      return docs.filter(function(doc) {
        return doc._rev !== winning._rev || JSON.stringify(doc) !== JSON.stringify(winning)
      })
      .map(function(doc) {
        if (doc._rev == winning._rev) return winning

        return {
          _id: doc._id,
          _rev: doc._rev,
          _deleted: true
        }

      })
    })
    .then(function(docs) {
      return db.bulkDocs(docs)
    })
  }
  else {
    var obj =
      _.mapKeys(_.omit(change.doc, ['_id', '_deleted']), function(val, key) {
                  return key == "_rev" ? "rev" : key
                })
    obj["deleted"] = change.doc._deleted ? true : false
    gingko.ports.change.send(
      [ change.id
      , obj
      ])
  }
}


function resolver(a, b) {
  console.log('resolver called', a, b)
  var m = _.clone(a)

  if (a.content !== b.content) {
    m.content = a.content + "\n=====CONFLICT=====\n" + b.content
    return m
  }
  else if (a.children !== b.children) {
    m.children = _.union(a.children, b.children)
    return m
  }
  else {
    return
  }
}


/* ===== DOM Manipulation ===== */

var setTextarea = (m, f) => {
  if(m.viewState.editing !== null && f !== null) {
    var textarea = document.getElementById('card-edit-'+m.viewState.editing)
    textarea.value = f
  }
}

var scrollHorizontal = colIdx => {
  lastColumnIdx = colIdx
  _.delay(scrollHorizTo, 20, colIdx)
}

var scrollColumns = centerlineIds => {
  lastCenterline = centerlineIds
  centerlineIds.map(function(c, i){
    var centerIdx = Math.round(c.length/2) - 1
    _.delay(scrollTo, 20, c[centerIdx], i)
  })
}

var scrollTo = function(cid, colIdx) {
  var card = document.getElementById('card-' + cid.toString());
  var col = document.getElementsByClassName('column')[colIdx+1]
  if (card == null) {
    console.log('scroll error: not found',cid)
    return;
  }
  var rect = card.getBoundingClientRect();

  TweenMax.to(col, 0.35,
    { scrollTop: col.scrollTop + ((rect.top + rect.height*0.5) - col.offsetHeight*0.5)
    , ease: Power2.easeInOut
    });
}

var scrollHorizTo = function(colIdx) {
  var col = document.getElementsByClassName('column')[colIdx+1]
  var appEl = document.getElementById('app');
  if (col == null) {
    console.log('scroll horiz error: not found', colIdx)
    return;
  }
  var rect = col.getBoundingClientRect();
  if (rect.width >= appEl.offsetWidth) {
    TweenMax.to(appEl, 0.50,
      { scrollLeft: appEl.scrollLeft + rect.left
      , ease: Power2.easeInOut
      });
  } else if (rect.left < 100) {
    TweenMax.to(appEl, 0.50,
      { scrollLeft: appEl.scrollLeft - 100 + rect.left
      , ease: Power2.easeInOut
      });
  } else if (rect.right > appEl.offsetWidth - 100) {
    TweenMax.to(appEl, 0.50,
      { scrollLeft: appEl.scrollLeft + 100 + rect.right - appEl.offsetWidth 
      , ease: Power2.easeInOut
      });
  }
}


/* ===== Shared variables ===== */

var shortcuts = [ 'mod+enter'
                , 'enter'
                , 'esc'
                , 'mod+backspace'
                , 'mod+j'
                , 'mod+k'
                , 'mod+l'
                , 'mod+down'
                , 'mod+up'
                , 'mod+right'
                , 'h'
                , 'j'
                , 'k'
                , 'l'
                , 'left'
                , 'down'
                , 'up'
                , 'right'
                , 'alt+left'
                , 'alt+down'
                , 'alt+up'
                , 'alt+right'
                , '['
                , ']'
                , 'mod+z'
                , 'mod+r'
                , 'mod+s'
                , 'mod+x' // debug command
                ];

var needOverride= [ 'mod+j'
                  , 'mod+k'
                  , 'mod+l'
                  , 'mod+s'
                  , 'mod+r'
                  , 'alt+left'
                  , 'alt+right'
                  ];

/* ===== CommonJS Module exports ===== */

module.exports =
  { scrollHorizontal: scrollHorizontal
  , scrollColumns: scrollColumns
  , saveModel: saveModel
  , loadModel: loadModel
  , onChange: onChange
  , resolver: resolver
  , shortcuts: shortcuts
  , needOverride: needOverride
  }
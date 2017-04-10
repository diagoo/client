module Trees exposing (..)

import Dict exposing (Dict)
import Tuple exposing (first, second)
import Html exposing (..)
import Html.Attributes exposing (..)
import Html.Events exposing (..)
import Html.Lazy exposing (lazy, lazy2, lazy3)
import Html.Keyed as Keyed
import Markdown

import Types exposing (..)
import TreeUtils exposing (..)
import Sha1 exposing (timeJSON)
import List.Extra as ListExtra



-- MODEL

type alias Model =
  { tree : Tree
  , columns : List Column
  , nodes : Dict String TreeNode
  }


defaultModel : Model
defaultModel =
  { tree = defaultTree
  , columns = getColumns [[[defaultTree]]]
  , nodes = Dict.fromList [("0", TreeNode "" [] Nothing False)]
  }


defaultTree : Tree
defaultTree =
  { id = "0"
  , content = ""
  , children = Children []
  , rev = Nothing
  , deleted = False
  }


blankTree : String -> Int -> Tree
blankTree timeString time =
  { id = generateId timeString time
  , content = ""
  , children = Children []
  , rev = Nothing
  , deleted = False
  }




-- UPDATE

type TreeMsg
  = NoOp
  | Ins Tree String Int
  | Upd String String
  | Mov Tree String Int
  | Del String
  | Node String TreeNode


type NodeMsg
  = Nope
  | Add String TreeNode String Int
  | Rmv String
  | Mod String String
  | Mv String String Int


update : TreeMsg -> Model -> Model
update msg model =
  case msg of
    Node id treeNode ->
      let
        newNodes =
          Dict.insert id treeNode model.nodes

        newTree =
          if newNodes /= model.nodes then
            nodesToTree newNodes "0"
              |> Result.withDefault defaultTree
          else
            model.tree

        newColumns =
          if newTree /= model.tree then
            getColumns [[[newTree]]]
          else
            model.columns
      in
      { model
        | tree = newTree
        , columns = newColumns
        , nodes = newNodes
      }

    _ ->
      model

updateColumns : Model -> Model
updateColumns model =
  { model
    | columns = getColumns [[[ model.tree ]]]
  }




-- ====== NODE UPDATES ======


updateData : Model -> Model
updateData model =
  let
    newTree =
      nodesToTree model.nodes "0"
        |> Result.withDefault defaultTree

    newColumns =
      if newTree /= model.tree then
        getColumns [[[newTree]]]
      else
        model.columns
  in
  { model
    | tree = newTree
    , columns = newColumns
  }


updateDataWithNodes : NodeMsg -> Model -> Model
updateDataWithNodes msg model =
  let
    newNodes =
      updateNodes msg model.nodes

    newTree =
      if newNodes /= model.nodes then
        nodesToTree newNodes "0"
          |> Result.withDefault defaultTree
          |> Debug.log "newNodes"
      else
        model.tree

    newColumns =
      if newTree /= model.tree then
        getColumns [[[newTree]]]
      else
        model.columns
  in
  { model
    | tree = newTree
    , columns = newColumns
    , nodes = newNodes
  }



updateNodes : NodeMsg -> Dict String TreeNode -> Dict String TreeNode
updateNodes msg nodes =
  case msg of
    Add id treeNode pid pos ->
      nodes
        |> Dict.insert id treeNode
        |> dictUpdate pid (insertChild id pos)

    Rmv id ->
      let
        parentId_ =
          getParentId id nodes

        updParent ptn =
          { ptn
          | children = ptn.children
              |> List.map
                  (\c -> if first c == id then (first c, False) else c)
          }
      in
      case parentId_ of
        Just parentId ->
          nodes
            |> dictUpdate id (\tn -> { tn | deleted = True } )
            |> dictUpdate parentId updParent

        Nothing ->
          nodes

    Mod id str ->
      nodes
        |> dictUpdate id (\tn -> { tn | content = str })

    Mv id newPid pos ->
      let
        oldPid_ =
          getParentId id nodes

        updParent ptn =
          { ptn
          | children = ptn.children
              |> List.filter
                  (\c -> first c /= id )
          }
      in
      case oldPid_ of
        Just oldPid ->
          nodes
            |> dictUpdate oldPid updParent
            |> dictUpdate newPid (insertChild id pos)

        Nothing ->
          nodes

    Nope ->
      nodes


insertChild : String -> Int -> TreeNode -> TreeNode
insertChild idToInsert idx treeNode =
  let
    visIdx_ =
      treeNode.children
        |> List.filter second
        |> ListExtra.getAt idx -- Maybe (String, Bool)
        |> Maybe.andThen (\sb -> ListExtra.elemIndex sb treeNode.children) -- Maybe Int

    ins i cs = (List.take i cs) ++ [(idToInsert, True)] ++ (List.drop i cs)
  in
  case visIdx_ of
    Just visIdx ->
      { treeNode
        | children = ins visIdx treeNode.children
      }

    Nothing ->
      { treeNode
        | children = ins 999999 treeNode.children
      }


getParentId : String -> Dict String TreeNode -> Maybe String
getParentId id nodes =
  nodes
    |> Dict.filter
        (\nid n ->
          n.children
            |> List.map first
            |> List.member id
        )
    |> Dict.toList
    |> List.map first
    |> List.head


insertTreeNode : String -> Int -> TreeNode -> TreeNode
insertTreeNode id idx treeNode =
  let
    refEl =
      treeNode.children
        |> List.filter second
        |> ListExtra.getAt (idx-1)
        |> Debug.log "refEl"
        |> Maybe.withDefault ("", False)

    fullIdx_ =
      ListExtra.elemIndex refEl treeNode.children -- Maybe Int
  in
  case fullIdx_ of
    Just fullIdx ->
      let
        fn children =
          (List.take (fullIdx+1) children)
          ++ [(id, True)]
          ++ (List.drop (fullIdx+1) children)
      in
      { treeNode
        | children = treeNode.children
            |> fn
      }

    Nothing ->
      treeNode





-- ====== TREE UPDATES ======


updateTree : TreeMsg -> Tree -> Tree
updateTree msg tree =
  case msg of
    NoOp -> tree

    Ins newTree parentId idx ->
      insertSubtree newTree parentId idx tree

    Upd id str ->
      modifyTree id (\t -> { t | content = str} ) tree

    Mov newTree parentId idx ->
      apply 
        [ Del newTree.id
        , Ins newTree parentId idx
        ]
      tree

    Del id ->
      pruneSubtree id tree

    Node id treeNode ->
      tree


apply : List TreeMsg -> Tree -> Tree
apply msgs tree =
  List.foldl (\m t -> updateTree m t) tree msgs


insertSubtree : Tree -> String -> Int -> Tree -> Tree
insertSubtree subtree parentId idx tree =
  let
    fn = (\c -> (List.take idx c) ++ [subtree] ++ (List.drop idx c))
  in
  modifyChildren parentId fn tree


pruneSubtree : String -> Tree -> Tree
pruneSubtree id tree =
  modifySiblings id (\c -> List.filter (\x -> x.id /= id) c) tree


modifyTree : String -> (Tree -> Tree) -> Tree -> Tree
modifyTree id upd tree =
  if tree.id == id then
    upd tree
  else
    { tree
      | children =
          getChildren tree
            |> List.map (modifyTree id upd)
            |> Children
    }


modifyChildren : String -> (List Tree -> List Tree) -> Tree -> Tree
modifyChildren pid upd tree =
  if tree.id == pid then
    { tree
      | children =
          getChildren tree
            |> upd
            |> Children
    }
  else
    { tree
      | children =
          getChildren tree
            |> List.map (modifyChildren pid upd)
            |> Children
    }


modifySiblings : String -> (List Tree -> List Tree) -> Tree -> Tree
modifySiblings id upd tree =
  case getParent id tree of
    Nothing ->
      tree
    Just parentTree ->
      modifyChildren parentTree.id upd tree




-- VIEW

view : ViewState -> Model -> Html Msg
view vstate model =
  let
    columnsWithDepth =
      model.columns
        |> List.indexedMap (\i c -> (c, i))

    getViewArgs cwd =
      let
        editing_ =
          case vstate.editing of
            Nothing ->
              Nothing

            Just editId ->
              if (first cwd |> List.concat |> List.map .id |> List.member editId ) then
                Just editId
              else
                Nothing
      in
      VisibleViewState 
        vstate.active
        editing_
        vstate.descendants

    columns =
      [([[]], -1)] ++
      columnsWithDepth ++
      [([[]], List.length columnsWithDepth)]
        |> List.map (\t -> lazy3 viewColumn (getViewArgs t) (second t) (first t))
  in
  div [ id "app" 
      ]
    ( columns
    )


viewColumn : VisibleViewState -> Int -> Column -> Html Msg
viewColumn vstate depth col =
  let
    buffer =
      [div [ class "buffer" ][]]
  in
  div
    [ class "column" ]
    ( buffer ++
      (List.map (lazy3 viewGroup vstate depth) col) ++
      buffer
    )
    


viewGroup : VisibleViewState -> Int -> Group -> Html Msg
viewGroup vstate depth xs =
  let
    firstChild = 
      xs
        |> List.head
        |> Maybe.withDefault defaultTree
        |> .id

    isActiveDescendant =
      vstate.descendants
        |> List.member firstChild

    viewFunction t =
      let
        isActive =
          t.id == vstate.active

        isEditing =
          case vstate.editing of
            Just editId ->
              t.id == editId

            Nothing ->
              False
      in
      viewKeyedCard (isActive, isEditing, depth) t
  in
    Keyed.node "div"
      [ classList [ ("group", True)
                  , ("active-descendant", isActiveDescendant)
                  ]
      ]
      (List.map viewFunction xs)


viewKeyedCard : (Bool, Bool, Int) -> Tree -> (String, Html Msg)
viewKeyedCard tup tree =
  (tree.id, lazy2 viewCard tup tree)


viewCard : (Bool, Bool, Int) -> Tree -> Html Msg
viewCard (isActive, isEditing, depth) tree =
  let
    isRoot = tree.id == "0"


    hasChildren =
      case tree.children of
        Children c ->
          ( c
              |> List.length
          ) /= 0

    tarea content =
      textarea
        [ id ( "card-edit-" ++ tree.id )
        , classList [ ("edit", True)
                    , ("mousetrap", True)
                    ]
        , defaultValue content
        ]
        []

    buttons =
      case (isEditing, isActive, isRoot) of
        ( False, True, False ) ->
          [ div [ class "flex-row card-top-overlay" ]
                [ span
                  [ class "card-btn ins-above"
                  , title "Insert Above (Ctrl+K)"
                  , onClick (InsertAbove tree.id)
                  ]
                  [ text "+" ]
                ]
          , div [ class "flex-column card-right-overlay"]
                [ span 
                  [ class "card-btn delete"
                  , title "Delete Card (Ctrl+Backspace)"
                  , onClick (DeleteCard tree.id)
                  ]
                  []
                , span
                  [ class "card-btn ins-right"
                  , title "Add Child (Ctrl+L)"
                  , onClick (InsertChild tree.id)
                  ]
                  [ text "+" ]
                , span 
                  [ class "card-btn edit"
                  , title "Edit Card (Enter)"
                  , onClick (OpenCard tree.id tree.content)
                  ]
                  []
                ]
          , div [ class "flex-row card-bottom-overlay" ]
                [ span
                  [ class "card-btn ins-below"
                  , title "Insert Below (Ctrl+J)"
                  , onClick (InsertBelow tree.id)
                  ]
                  [ text "+" ]
                ]
          ]

        ( False, True, True ) ->
          [ div [ class "flex-column card-right-overlay"]
                [ span
                  [ class "card-btn ins-right"
                  , title "Add Child (Ctrl+L)"
                  , onClick (InsertChild tree.id)
                  ]
                  [ text "+" ]
                , span 
                  [ class "card-btn edit"
                  , title "Edit Card (Enter)"
                  , onClick (OpenCard tree.id tree.content)
                  ]
                  []
                ]
          ]

        ( True, _, _ ) ->
          [ div [ class "flex-column card-right-overlay"]
                [ span 
                  [ class "card-btn save"
                  , title "Save Changes (Ctrl+Enter)"
                  , onClick (AttemptUpdateCard tree.id)
                  ]
                  []
                ]
          ]

        _ ->
          []


    cardAttributes =
      [ id ("card-" ++ tree.id)
      , classList [ ("card", True)
                  , ("root", isRoot)
                  , ("active", isActive)
                  , ("editing", isEditing)
                  , ("has-children", hasChildren)
                  ]
      ]
  in
  if isEditing then
    div cardAttributes
      (
        [ tarea tree.content ]
        ++
        buttons
      )
  else
    div cardAttributes
      (
        buttons ++
        [ div
            [ class "view"
            , onClick (Activate tree.id)
            , onDoubleClick (OpenCard tree.id tree.content)
            ] 
            [( lazy viewContent tree.content )]
        ]
      )


viewContent : String -> Html Msg
viewContent content =
  let
    options =
      { githubFlavored = Just { tables = True, breaks = True }
      , defaultHighlighting = Nothing
      , sanitize = False
      , smartypants = False
      }
  in
  Markdown.toHtmlWith options
    [] content


{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE OverloadedStrings #-}

module Smos.Report.Query where

import GHC.Generics (Generic)

import Data.Char as Char
import Data.Function
import qualified Data.Text as T
import Data.Text (Text)
import Data.Validity
import Data.Void

import Control.Monad

import Lens.Micro

import Text.Megaparsec
import Text.Megaparsec.Char

import Cursor.Simple.Forest
import Cursor.Simple.Tree
import Smos.Data

data Filter
    = FilterHasTag Tag
    | FilterTodoState TodoState
    | FilterParent Filter
    | FilterAncestor Filter
    | FilterNot Filter
    | FilterAnd Filter
                Filter
    | FilterOr Filter
               Filter
    deriving (Show, Eq, Generic)

instance Validity Filter

filterPredicate :: Filter -> ForestCursor Entry -> Bool
filterPredicate f fc =
    case f of
        FilterHasTag t -> t `elem` entryTags cur
        FilterTodoState mts -> Just mts == entryState cur
        FilterParent f' -> maybe False (filterPredicate f') parent
        FilterAncestor f' ->
            maybe
                False
                (\fc_ -> filterPredicate f' fc_ || filterPredicate f fc_)
                parent
        FilterNot f' -> not $ filterPredicate f' fc
        FilterAnd f1 f2 -> filterPredicate f1 fc && filterPredicate f2 fc
        FilterOr f1 f2 -> filterPredicate f1 fc || filterPredicate f2 fc
  where
    parent :: Maybe (ForestCursor Entry)
    parent = fc & forestCursorSelectedTreeL treeCursorSelectAbove
    cur :: Entry
    cur = fc ^. forestCursorSelectedTreeL . treeCursorCurrentL

type P = Parsec Void Text

parseFilter :: Text -> Maybe Filter
parseFilter = parseMaybe filterP

filterP :: P Filter
filterP =
    try filterHasTagP <|> try filterTodoStateP <|> try filterParentP <|>
    try filterAncestorP <|>
    try filterNotP <|>
    filterBinRelP

filterHasTagP :: P Filter
filterHasTagP = do
    void $ string' "tag:"
    s <-
        many
            (satisfy $ \c ->
                 Char.isPrint c && not (Char.isSpace c) &&
                 not (Char.isPunctuation c))
    either fail (pure . FilterHasTag) $ parseTag $ T.pack s

filterTodoStateP :: P Filter
filterTodoStateP = do
    void $ string' "state:"
    s <-
        many
            (satisfy $ \c ->
                 Char.isPrint c && not (Char.isSpace c) &&
                 not (Char.isPunctuation c))
    either fail (pure . FilterTodoState) $ parseTodoState $ T.pack s

filterParentP :: P Filter
filterParentP = do
    void $ string' "parent:"
    FilterParent <$> filterP

filterAncestorP :: P Filter
filterAncestorP = do
    void $ string' "ancestor:"
    FilterAncestor <$> filterP

filterNotP :: P Filter
filterNotP = do
    void $ string' "not:"
    FilterNot <$> filterP

filterBinRelP :: P Filter
filterBinRelP = do
    void $ char '('
    f <- try filterOrP <|> filterAndP
    void $ char ')'
    pure f

filterOrP :: P Filter
filterOrP = do
    f1 <- filterP
    void $ string' " or "
    f2 <- filterP
    pure $ FilterOr f1 f2

filterAndP :: P Filter
filterAndP = do
    f1 <- filterP
    void $ string' " and "
    f2 <- filterP
    pure $ FilterAnd f1 f2

renderFilter :: Filter -> Text
renderFilter f =
    case f of
        FilterHasTag t -> "tag:" <> tagText t
        FilterTodoState ts -> "state:" <> todoStateText ts
        FilterParent f' -> "parent:" <> renderFilter f'
        FilterAncestor f' -> "ancestor:" <> renderFilter f'
        FilterNot f' -> "not:" <> renderFilter f'
        FilterOr f1 f2 ->
            T.concat ["(", renderFilter f1, " or ", renderFilter f2, ")"]
        FilterAnd f1 f2 ->
            T.concat ["(", renderFilter f1, " and ", renderFilter f2, ")"]

module Smos.Cursor.TagsSpec where

import Test.Hspec
import Test.Validity

import Smos.Data.Gen ()

import Smos.Cursor.Tags
import Smos.Cursor.Tags.Gen ()

spec :: Spec
spec = do
    describe "makeTagsCursor" $
        it "produces valid cursors" $ producesValidsOnValids makeTagsCursor
    describe "rebuildTagsCursor" $ do
        it "produces valid cursors" $ producesValidsOnValids rebuildTagsCursor
        it "is the inverse of makeTagsCursor" $
            inverseFunctionsOnValid makeTagsCursor rebuildTagsCursor

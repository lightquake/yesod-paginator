{-# LANGUAGE RecordWildCards #-}
{-# LANGUAGE QuasiQuotes       #-}
{-# LANGUAGE OverloadedStrings #-}
module Yesod.Paginator.Widget
 ( getCurrentPage
 , paginationWidget
 , defaultWidget
 , PageWidget
 , PageWidgetConfig(..)
 ) where

import           Yesod

import           Control.Monad (when)
import           Data.Maybe    (fromMaybe)
import           Data.Text (Text)
import qualified Data.Text as T

type PageWidget s m = Int -> Int -> Int -> GWidget s m ()

data PageWidgetConfig = PageWidgetConfig {
   prevText   :: Text    -- ^ The text for the 'previous page' link.
 , nextText   :: Text    -- ^ The text for the 'next page' link.
 , pagesCount :: Int -- ^ The number of page links to show
 , ascending  :: Bool -- ^ Whether to list pages in ascending order.
}

-- | Individual links to pages need to follow strict (but sane) markup
--   to be styled correctly by bootstrap. This type allows construction
--   of such links in both enabled and disabled states.
data PageLink = Enabled Int Text Text -- ^ page, content, class
              | Disabled    Text Text -- ^ content, class


-- | Correctly show one of the constructed links
showLink :: [(Text, Text)] -> PageLink -> GWidget s m ()
showLink params (Enabled pg cnt cls) = do
    let param = ("p", showT pg)

    [whamlet|
        <li .#{cls}>
            <a href="#{updateGetParam params param}">#{cnt}
        |]

    where
        updateGetParam :: [(Text,Text)] -> (Text,Text) -> Text
        updateGetParam getParams (p, n) = (T.cons '?') . T.intercalate "&"
                                        . map (\(k,v) -> k `T.append` "=" `T.append` v)
                                        . (++ [(p, n)]) . filter ((/= p) . fst) $ getParams

showLink _ (Disabled cnt cls) =
    [whamlet|
        <li .#{cls} .disabled>
            <a>#{cnt}
        |]

defaultWidget :: PageWidget s m
defaultWidget = paginationWidget $ PageWidgetConfig { prevText = "«"
                                                    , nextText = "»"
                                                    , pagesCount = 9
                                                    , ascending = True}

-- | A widget showing pagination links. Follows bootstrap principles.
--   Utilizes a \"p\" GET param but leaves all other GET params intact.
paginationWidget :: PageWidgetConfig -> PageWidget s m
paginationWidget (PageWidgetConfig {..}) page per tot = do
    -- total / per + 1 for any remainder
    let pages = (\(n, r) -> n + (min r 1)) $ tot `divMod` per

    when (pages > 1) $ do
        curParams <- lift $ fmap reqGetParams getRequest

        [whamlet|
            <ul>
                $forall link <- buildLinks page pages
                    ^{showLink curParams link}
            |]

    where
        -- | Build up each component of the overall list of links. We'll
        --   use empty lists to denote ommissions along the way then
        --   concatenate.
        buildLinks :: Int -> Int -> [PageLink]
        buildLinks pg pgs =
            let prev = [1      .. pg - 1]
                next = [pg + 1 .. pgs   ]

                -- these always appear
                prevLink = [(if null prev then Disabled else Enabled (pg - 1)) prevText "prev"]
                nextLink = [(if null next then Disabled else Enabled (pg + 1)) nextText "next"]

                -- show first/last unless we're on it
                firstLink = [ Enabled 1   "1"        "prev" | pg > 1   ]
                lastLink  = [ Enabled pgs (showT pgs) "next" | pg < pgs ]

                -- we'll show ellipsis if there are enough links that some will
                -- be ommitted from the list
                prevEllipsis = [ Disabled "..." "prev" | length prev > pagesCount + 1 ]
                nextEllipsis = [ Disabled "..." "next" | length next > pagesCount + 1 ]

                -- the middle lists, strip the first/last pages and
                -- correctly take up to limit away from current
                prevLinks = reverse . take pagesCount . reverse . drop 1 $ map (\p -> Enabled p (showT p) "prev") prev
                nextLinks = take pagesCount . reverse . drop 1 . reverse $ map (\p -> Enabled p (showT p) "next") next

                -- finally, this page itself
                curLink = [Disabled (showT pg) "active"]

            in concat $ (if ascending then id else reverse) [ prevLink
                      , firstLink
                      , prevEllipsis
                      , prevLinks
                      , curLink
                      , nextLinks
                      , nextEllipsis
                      , lastLink
                      , nextLink
                      ]

-- | looks up the \"p\" GET param and converts it to an Int. returns a
--   default of 1 when conversion fails.
getCurrentPage :: GHandler s m Int
getCurrentPage = fmap (fromMaybe 1 . go) $ lookupGetParam "p"

    where
        go :: Maybe Text -> Maybe Int
        go mp = readIntegral . T.unpack =<< mp

showT :: (Show a) => a -> Text
showT = T.pack . show
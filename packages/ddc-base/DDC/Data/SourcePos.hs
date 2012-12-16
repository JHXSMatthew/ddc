
module DDC.Data.SourcePos
        (SourcePos (..))
where
import DDC.Base.Pretty


-- | A position in a source file.        
--
--   If there is no file path then we assume that the input has been read
--   from an interactive session and display ''<interactive>'' when pretty printing.
data SourcePos 
        = SourcePos
        { sourcePosSource       :: String
        , sourcePosLine         :: Int
        , sourcePosColumn       :: Int }
        deriving (Eq, Show)


instance Pretty SourcePos where
 -- Suppress printing of line and column number when they are both zero.
 -- File line numbers officially start from 1, so having 0 0 probably
 -- means this isn't real information.
 ppr (SourcePos source 0 0)
        = ppr $ source

 ppr (SourcePos source l c)     
        = ppr $ source ++ ":" ++ show l ++ ":" ++ show c


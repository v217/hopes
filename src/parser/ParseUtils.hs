module ParseUtils where

import HpSyn
import Types
import Loc
import Err
import Pretty

import List (partition)
import Maybe (catMaybes)
import Char (isUpper)
import System.IO
import Control.Monad.State
import Control.Monad.Identity

import Debug.Trace

type StringBuffer = String

data Token =
      TKoparen
    | TKcparen
    | TKgets
    | TKdot
    | TKcomma
    | TKvert
    | TKobrak
    | TKcbrak
    | TKocurly
    | TKccurly
    | TKwild
    | TKcolcol
    | TKsemi
    | TKcut
    | TKslash
    | TKbslash
    | TKarrow
    | TKid String
    | TKEOF
   deriving Eq

type Parser = StateT ParseState (ErrorT Messages Identity)

data ParseState = PState {
    buffer   :: StringBuffer,
    --last_loc :: Loc,
    last_tok :: Located Token,
    cur_tok  :: Located Token,
    loc      :: Loc }
    deriving Show


getSrcBuf :: Parser StringBuffer
getSrcBuf = gets buffer

setSrcBuf :: StringBuffer -> Parser ()
setSrcBuf inp = modify (\s -> s{buffer=inp})

getSrcLoc :: Parser Loc
getSrcLoc = gets loc

setSrcLoc :: Loc -> Parser ()
setSrcLoc l = modify (\s -> s{loc=l})

setLastTok :: Located Token -> Parser ()
setLastTok t = modify (\s -> s{cur_tok=t, last_tok = (cur_tok s)})

getLastTok :: Parser (Located Token)
getLastTok = gets last_tok

getTok :: Parser (Located Token)
getTok = gets cur_tok

runParser p s = runIdentity $ runErrorT $ runStateT p s

parseFromFile p fname = do 
    file <- openFile fname ReadMode
    inp <- hGetContents file
    let result = runParser p (mkStateWithFile inp fname)
    return result


mkStateWithFile inp file = PState inp tok tok loc
    where loc = Loc file 1 1
          tok = undefined

mkState :: String -> ParseState
mkState input = mkStateWithFile input "stdin"

getName :: Located Token -> HpName
getName (L _ (TKid x)) = x
getName _ = error "not a valid token"


data HpType   =
      HpTyGrd HpName                    -- ground type
    | HpTyFun LHpType LHpType           -- type of function
    | HpTyTup [LHpType]                 -- type of tuple
    | HpTyRel LHpType                   -- type of relation / isomorfic to a function type

type LHpType   = Located HpType

mkTyp :: LHpType -> Parser Type
mkTyp (L _ (HpTyGrd "o"))  = return (TyCon TyBool)
mkTyp (L _ (HpTyGrd "i"))  = return (TyCon TyAll)
mkTyp (L _ (HpTyFun t1 t2)) = do
    t1' <- mkTyp t1
    t2' <- mkTyp t2
    return (TyFun t1' t2')
mkTyp (L _ (HpTyRel t))    = do
    t' <- mkTyp t
    return (TyFun t' (TyCon TyBool))
mkTyp (L _ (HpTyTup tl))   = do
    tl' <- mapM mkTyp tl
    case tl' of
        [t] -> return t 
        _ -> return (TyTup tl')

mkTyp (L l t) = parseErrorWithLoc (spanBegin l) (text "Not a valid type")


type HpStmt   = Either LHpClause LHpTySign

collectEither :: [Either a b] -> ([a], [b])
collectEither es = (map unL l, map unR r)
    where isLeft (Left _) = True
          isLeft _ = False
          unL (Left a)  = a
          unR (Right a) = a
          (l, r) = partition isLeft es

mkSrc :: [HpStmt] -> Parser HpSource
mkSrc stmts = 
    let (l, r) = collectEither stmts
        hsymM  = mapM (getId.headOf.hAtom) l
    in  do
        hsym <- hsymM
        l' <- mapM (fixSym (hsym,[])) l
        return HpSrc { clauses = l',  tysigs = r }

type SymbEnv = ([HpName], [HpName])

fixSym :: SymbEnv -> LHpClause -> Parser LHpClause
fixSym (ds,bs) (L loc (HpClaus v h b)) = do
    h' <- fixSymE (ds, bs ++ v) h
    b' <- mapM (fixSymE (ds, bs ++ v)) b
    return (L loc (HpClaus v h' b'))

fixSymE :: SymbEnv -> LHpExpr -> Parser LHpExpr
fixSymE env (L loc (HpPar e)) = do
    e' <- fixSymE env e
    return $ L loc (HpPar e')
fixSymE env (L loc (HpAnn e t)) = do
    e' <- fixSymE env e
    return $ L loc (HpAnn e' t)
fixSymE env (L loc (HpApp e1 e2)) = do
    e1' <- fixSymE env e1
    e2' <- mapM (fixSymE env) e2
    return $ L loc (HpApp e1' e2')
fixSymE env (L loc (HpTup es)) = do
    es' <- mapM (fixSymE env) es
    return (L loc (HpTup es'))
fixSymE (ds, bs) e@(L loc (HpSym s)) =
    if s `elem` bs then
        return (L loc (HpVar s))
    else if s `elem` ds then
        return (L loc (HpPre s))
    else
        return e

quant :: HpName -> Bool
quant = isUpper.head

mkClause :: LHpExpr -> [LHpExpr] -> HpClause
mkClause hd bd = 
    let sym   = concatMap symbolsE (hd:bd)
        vars' = filter quant sym
    in  HpClaus vars' hd bd

mkGoal :: [LHpExpr] -> HpGoal
mkGoal es =
    let vars  = catMaybes $ map getId $ map headOf es
        vars' = filter quant vars
    in  HpGoal vars es

parseErrorWithLoc loc msg = 
    throwError $ mkMsgs $ mkErrWithLoc loc ParseError Failure msg []

parseError msg = do
    tok <- gets cur_tok
    let loc = spanBegin $ getLoc tok
    parseErrorWithLoc loc msg

instance Show Token where
    showsPrec n (TKoparen) = showString "("
    showsPrec n (TKcparen) = showString ")"
    showsPrec n (TKgets)   = showString ":-"
    showsPrec n (TKdot)    = showString "."
    showsPrec n (TKcomma)  = showString ","
    showsPrec n (TKvert)   = showString "|"
    showsPrec n (TKobrak)  = showString "["
    showsPrec n (TKcbrak)  = showString "]"
    showsPrec n (TKocurly) = showString "{"
    showsPrec n (TKccurly) = showString "}"
    showsPrec n (TKwild)   = showString "_"
    showsPrec n (TKcolcol) = showString "::"
    showsPrec n (TKsemi)   = showString ";"
    showsPrec n (TKcut)    = showString "!"
    showsPrec n (TKslash)  = showString "/"
    showsPrec n (TKbslash) = showString "\\"
    showsPrec n (TKarrow)  = showString "->"
    showsPrec n (TKid s)   = showString s

type LTok = Located Token

mkLTk = mkLoc

instance Pretty Token where
    ppr t = text (show t)
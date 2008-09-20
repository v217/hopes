--  Copyright (C) 2006-2008 Angelos Charalambidis <a.charalambidis@di.uoa.gr>
--
--  This program is free software; you can redistribute it and/or modify
--  it under the terms of the GNU General Public License as published by
--  the Free Software Foundation; either version 2, or (at your option)
--  any later version.
--
--  This program is distributed in the hope that it will be useful,
--  but WITHOUT ANY WARRANTY; without even the implied warranty of
--  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
--  GNU General Public License for more details.
--
--  You should have received a copy of the GNU General Public License
--  along with this program; see the file COPYING.  If not, write to
--  the Free Software Foundation, Inc., 51 Franklin Street, Fifth Floor,
--  Boston, MA 02110-1301, USA.

module Infer where

import Hopl
import KnowledgeBase
import Subst
import Logic

import Types
import Lang

import Control.Monad.Reader
import Control.Monad.State
import Control.Monad.Identity
-- import Data.Monoid
-- import List (last)
import Debug.Trace
import Pretty


type Infer a = ReaderT (KnowledgeBase a) (StateT Int (LogicT Identity))

runInfer p m = runIdentity $ runLogic Nothing $ evalStateT (runReaderT m p) 0

infer :: KnowledgeBase a -> Infer a b -> Maybe (b, Infer a b)
infer p m =  runIdentity $ observe $ evalStateT (runReaderT (msplit m) p) 0

-- try prove a formula by refutation
-- prove  :: Goal a -> Infer a (Subst a)
prove g =  do
    ans <- refute g
    return (restrict (vars g) ans)

-- do a refutation
-- refute :: Goal a -> Infer a (Subst a)
refute g
    | isContra g = return success
    | otherwise  = trace ("deriving " ++ (show (ppr g))) $ derive g >>- \(g',  s)  ->
                   refute (subst s g') >>- \ans ->
                   return (s `combine` ans)

-- a derivation
-- derive :: Goal a -> Infer a (Goal a, Subst a)
derive g
  | isContra g = return (contradiction, success)
  | otherwise =
    let f g = case functor g of
                 Rigid _    -> trace ("Rigid resolution") $ resolve g
                 Flex _     -> trace ("Flex resolution") $ resolveF g
                 Lambda _ _ -> trace ("Beta reduce" ++ (show (ppr g))) $ betareduce g
                 _ -> error  "Cannot derive anything from that atom"
    -- in undefined -- split g  >>- \(a, g') -> f g' a
    in case g of
        (App (App c a) b) ->
            if c == cand then
                derive a >>- \(g', s) ->
                    if isContra g' then
                        trace ("cand contra derived " ++ (show (ppr a))) $ return (b, s)
                    else
                        trace ("cand derived " ++ (show (ppr a)) ++ " yielding " ++ (show (ppr g'))) $ return ((App (App cand g') b), s)
            else if c == cor then
                return a `mplus` return b >>- \g ->
                    derive g
            else if c == ceq then
                unify a b >>= \s ->
                trace ("Unify " ++ (show (ppr a)) ++ " and " ++
                      (show (ppr b)) ++ " subst " ++ (show (ppr s))) $
                return (contradiction, s)
            else if c == ctop then
                return (contradiction, success)
            else if c == cbot then
                fail "cbot"
            else f g
        _ -> f g

-- derive by resolution (the common rigid case)
-- FIXME: clause assumed to be a tuple.
--        goal assumed to be equivalent to the body of a clause
-- resolve :: Goal a -> Expr a -> Infer a (Goal a, Subst a)
{-
resolve g e = 
    clausesOf e >>- \c     ->
    variant c   >>- \(h,b) ->
    unify e h   >>- \s     ->
    return (b `mappend` g, s)
-}


substExp (App e a) b = (App (substExp e b) a)
substExp _ b = b


resolve g =
    clauseOf (functor g) >>- \c ->
    variant c >>- \(C p b) ->
    return (substExp g b, success)

{-
betareduce (App (Lambda x e) a) =
    let subst (Flex v) = if v == x then a else (Flex v)
        subst (App e e') = (App (subst e) (subst e'))
        subst (Lambda y e) = (Lambda y (subst e))
        subst (Const c) = (Const c)
        subst (Rigid r) = (Rigid r)
    in  betareduce (subst e)
-}

betareduce (App e a) = do
        (e',s) <- betareduce e
        case e' of
            Lambda x e'' ->
                return (subst (bind x a) e'', s)
            _ -> return ((App e' a), s)
betareduce e = return (e, success)

resolveF g =
    let f = functor g
    in case f of
          (Flex x) ->
              singleInstance (typeOf f) >>- \fi -> do
              r <- freshVarOfType (typeOf f)
              return ((substExp g fi), (bind x (lubExp fi (Flex r))))
          _ -> fail "resolveF: cannot resolve a non flexible"


{-
lambdaInstance ty
    | ty == tyBool = return cbot `mplus` return ctop
    | ty == tyAll  = error "cannot lambda instantiate an individual"
    | otherwise    =
        case ty of
            TyFun f a -> undefined
-}
lubExp e1 e2 =
    let lubExp1 (Lambda x e) e' bs =
            (Lambda x (lubExp1 e e' (x:bs)))
        lubExp1 e e' bs = (App (App cor e) e'')
            where e'' = foldl (\x -> \y -> (App x (Flex y))) e' bs
    in  lubExp1 e1 e2 []

comb e' (Lambda x e) = (Lambda x (comb e' e))
comb e' e = (App (App cand e') e)

appInst e = do
    case typeOf e of
        TyFun t1 t2 -> do
            a <- basicInstance t1
            appInst (App e a)
        _ -> return e


disjLambda [] = return cbot
disjLambda (e:es) =
    case typeOf e of
        TyFun t1 t2 -> do
            x <- freshVarOfType t1
            let vs'  = map (\(Lambda v _) -> v) (e:es)
            let es'  = map (\(Lambda _ e') -> e') (e:es)
            let ss'  = zip (map (\v -> bind v (Flex x)) vs') es'
            let es'' = map (\(s,e) -> subst s e) ss'
            e' <- disjLambda es''
            return (Lambda x e')
        _ -> return $ foldl (\x -> \y -> (App (App cor x) y)) e es


basicInstance ty@(TyFun ty_arg ty_res) =
    msum (map return [1..]) >>- \n ->
    (sequence $ take n $ repeat (singleInstance ty)) >>- \le ->
    disjLambda le
basicInstance x = singleInstance x


singleInstance (TyFun ty_arg ty_res) = do
    x   <- freshVarOfType ty_arg
    xe  <- case ty_arg of
             TyFun a b ->
                    msum (map return [1..]) >>- \n ->
                    (sequence $ take n $ repeat $ appInst (Flex x)) >>- \le -> 
                    return $ foldl (\e -> \e2 -> (App (App cand e) e2)) (head le) (tail le)
             _ -> if ty_arg == tyAll then do
                        y <- singleInstance ty_arg
                        return (App (App ceq (Flex x)) y)
                  else if ty_arg == tyBool then do
                        y <- singleInstance ty_arg
                        return $ if y == ctop then (Flex x) else ctop
                  else
                        fail ""
    res <- singleInstance ty_res
    return $ if (ty_res == tyBool) then (Lambda x xe) else (Lambda x (comb xe res))

singleInstance ty
    | ty == tyBool = return cbot `mplus` return ctop
    | ty == tyAll  = freshVarOfType ty >>= \x -> return (Flex x)
    | otherwise = fail "cannot instantiate from type"



{-
resolvS g (App (Set ss vs) e) = do
    let v = last vs             -- SEARCH ME: any solutions lost? discard all variables except the last one (which is continuous?)
    let TyFun a r = typeOf v
    x  <- freshIt v
    let x' = typed a (unTyp x)
    (Flex x') `waybelow` e >>- \s -> do
        v' <- freshIt v
        return (g, (bind v (Set [(Flex x')] [v'])) `combine` s)
-}

-- unification

unify :: (Eq a, Monad m) => Expr a -> Expr a -> m (Subst a)

unify (Flex v1) e@(Flex v2)
    | v1 == v2  = return success
    | otherwise = return (bind v1 e)

unify (Flex v) t = do
    occurCheck v t
    return (bind v t)

unify t1 t2@(Flex v) = unify t2 t1

unify (App e1 e2) (App e1' e2') = do
    s1 <- unify e1 e1'
    s2 <- unify (subst s1 e2) (subst s1 e2')
    return (s1 `combine` s2)

-- unify (Tup es) (Tup es') = listUnify es es'

unify (Rigid p) (Rigid q)
    | p == q    = return success
    | otherwise = fail "Unification fail"

unify _ _ = fail "Should not happen"

{-
listUnify  :: (Eq a, Monad m) => [Expr a] -> [Expr a] -> m (Subst a)
listUnify [] [] = return success
listUnify (e1:es1) (e2:es2) = do
    s <- unify e1 e2
    s' <- listUnify (map (subst s) es1) (map (subst s) es2)
    return (s `combine` s')

listUnify _ _   = fail "lists of different length"
-}

occurCheck :: (Eq a, Monad m) => a -> Expr a -> m ()
occurCheck a e = when (a `occursIn` e) $ fail "Occur Check"

occursIn a e = a `elem` (vars e)


{-
    (waybelow x y) successed with a substitution if x is waybelow of y
    waybelow can successed more than once e.g. for all x that are waybelow y
    waybelow fails if no substitution exists to make x waybelow y
-}
-- waybelow :: MonadLogic m => Expr a -> Expr a -> m Subst
-- if p is higher order we want a finitary subset S
-- if p is zero order just unify x with p

{-
waybelow (Flex x) (Rigid p)
    | order p == 0 = unify (Flex x) (Rigid p)
    | otherwise    = error "last to implement"
        -- prove (p(X1, ..., XN)) = [s1, s2, ...]

-- possibly a function symbol application (remember no partial applications allowed, so that can't be higher order)
waybelow e1@(Flex _) e2@(App _ _) = unify e1 e2

waybelow (Flex x) (Set sl vs@(v:_)) = do
    v' <- freshIt v
    return $ bind v (Set [] [x, v'])

waybelow e1@(Flex _) e2@(Flex v)
    | order v == 0 = unify e1 e2
    | otherwise    = waybelow e1 (liftSet e2)

waybelow (Flex x) e@(Tup es) = do
    xs <- mapM (\e -> freshIt x) es
    let xs' = Tup (map Flex xs)
    s <- waybelow xs' e
    return $ combine (bind x xs') s

waybelow (Tup es) (Tup es') = do
    ss <- zipWithM waybelow es es'
    return (foldl combine success ss)

-- can't go in this case. Defined just for completeness.
waybelow (Rigid p) (Rigid q) 
    | p == q    = return success -- same intensions -> same extensions
    | otherwise = fail "cannot compute if one rigid symbol is waybelow of some other rigid symbol"
-}

-- utils

-- split a goal to an atom and the rest goal
-- deterministic computation picking always the left-most atom
-- split :: Goal a -> Infer a (Expr a, Goal a)
split []     = fail "Empty goal. Can't pick an atom"
split (x:xs) = return (x, xs)

{-
clausesOf (App q _) = do
    p <- asks clauses
    let cl = filter (\(App r _, b)-> r == q) p
    msum (map return cl)
-}
clauseOf (Rigid r) = do
    p <- asks clauses
    let cl = filter (\(C p' _) -> p' == r) p
    msum (map return cl)
clauseOf e = fail "expression must be rigid (parameter)"

-- make a fresh variant of a clause.
-- monadic computation because of freshVar.
-- variant :: Clause a -> Infer a (Clause a)
-- FIXME: subst assumed to be list 
-- PITFALL: flexs are computed every time

variant c =
    let vs = vars c
        bindWithFresh v = do
            v' <- freshVarOfType (typeOf v)
            return (v, Flex v')
    in do
    s <- mapM bindWithFresh vs
    return $ subst s c

freshVarOfType :: (MonadState Int m, Symbol a, HasType a) => Type -> m a
freshVarOfType ty = do
    a' <- get
    modify (+1)
    return $ hasType ty $ liftSym ("_S" ++ show a')
{-
freshIt :: (MonadState Int m, Functor f, Symbol a) => f a -> m (f a)
freshIt s = do
    a' <- get
    modify (+1)
    return $ fmap (const (liftSym ("_S" ++ show a'))) s
-}
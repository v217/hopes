--  Copyright (C) 2013 Angelos Charalambidis <a.charalambidis@di.uoa.gr>
--                     Emmanouil Koukoutos   <manoskouk@softlab.ntua.gr>
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

module Syntax where

import Types
import Basic
import Pos

{-
 - Concrete syntax tree for the surface language.
 - Expressions are polymorphic to include extra information,
 - which will vary depending on the context.
 -}

-- Description of constants and variables.
data Const a = Const a Symbol -- info and name 
    deriving Functor

data Var a = Var a Symbol -- named variable
           | AnonVar a    -- wildcard
    deriving Functor

{-
 - The syntactic structures are organized recursively 
 - in inclusion order
 -}

-- Any sentence of the program
data SSent a = SSent_clause (SClause  a)
             | SSent_goal   (SGoal    a)
             | SSent_comm   (SCommand a)
    deriving Functor

-- A goal sentence
data SGoal a = SGoal a (SExpr a)
    deriving Functor

-- A directive
data SCommand a = SCommand a (SExpr a)
    deriving Functor

-- A clause. If clBody is Just we have a rule, else a fact
data SClause a = SClause { clInfo :: a 
                         , clHead :: SExpr a --SHead a
                         , clBody :: Maybe (SGets, SExpr a)
                         }
    deriving Functor

-- Monomorphic or polymorphic gets
data SGets = SGets_mono | SGets_poly 

-- Expressions 
data SExpr a = SExpr_const   a            -- constant 
                             (Const a)    -- id
                             Bool         -- interpreted as predicate?
                             (Maybe Int)  -- optional GIVEN arity 
                             Int          -- INFERRED arity
             | SExpr_var     a (Var a)    -- variable
             | SExpr_number  a (Either Integer Double)
                                          -- numeric constant
             | SExpr_predCon a            -- predicate constant
                             (Const a)    -- id
                             (Maybe Int)  -- optional GIVEN arity
                             Int          -- INFERRED arity
             | SExpr_app  a (SExpr a) [SExpr a]  -- application
             | SExpr_op   a          -- operator
                          (Const a)  -- id
                          Bool       -- interpreted as pred?
                          [SExpr a]  -- arguments
             | SExpr_lam  a [Var a] (SExpr a)    -- lambda abstr.
             | SExpr_list a [SExpr a] (Maybe (SExpr a))
                          -- list: initial elements, maybe tail
             | SExpr_ann  a (SExpr a) RhoType    -- type annotated
    deriving Functor


-- The following types represent the organization used
-- by the type checker

-- All clauses defining a predicate
data SPredDef a = SPredDef { predDefName    :: Symbol
                           , predDefArity   :: Int
                           , predDefClauses :: [SClause a]
                           } 
    deriving Functor

-- A dependency group
type SDepGroup a = [SPredDef a]

-- All predicate definitions, organized into dependency groups in DAG order
type SDepGroupDag a = [SDepGroup a]



{- 
 - Utility functions for the syntax tree of polyHOPES
 -}

-- Print syntax tree
-- TODO make them better
deriving instance Show a => Show (Const a)
deriving instance Show a => Show (Var a)
deriving instance Show a => Show (SClause a)
deriving instance           Show SGets
deriving instance Show a => Show (SExpr a)
deriving instance Show a => Show (SGoal a)
deriving instance Show a => Show (SCommand a)
deriving instance Show a => Show (SSent a)

instance Show a => Show (SPredDef a) where
    show (SPredDef nm ar cls) = 
        nm ++ "/" ++ show ar ++ "\n" ++ foldr (\cl rest -> show cl ++ "\n" ++ rest) "" cls

{-
 - Simple predicates, utility functions, and class declarations 
 - on syntax structures
 -}

-- 1) constants, variables
instance HasName (Const a) where 
    nameOf (Const _ nm) = nm
instance HasName (Var a ) where 
    nameOf (Var _ nm)  = nm
    nameOf (AnonVar _) = "_" 

instance HasPosition a => HasPosition (Const a) where
    posSpan (Const a _)  = posSpan a  
instance HasPosition a => HasPosition (Var a) where
    posSpan (Var a _)  = posSpan a
    posSpan (AnonVar a) = posSpan a

-- Is a variable anonymous?
isAnon (AnonVar _ ) = True
isAnon _ = False 


-- Sentences
isGoal (SSent_goal _) = True
isGoal _ = False 

isClause (SSent_clause _) = True 
isClause _ = False

isCommand (SSent_comm _) = True
isCommand _ = False


-- PredDef

instance HasName (SPredDef a) where 
    nameOf = predDefName
instance HasArity (SPredDef a) where
    arity = Just . predDefArity


-- Clauses
instance HasName (SClause a) where 
    nameOf = nameOf.clHead
instance HasArity (SClause a) where
    arity = arity.clHead

isFact :: SClause a -> Bool
isFact (SClause _ _ Nothing) = True
isFact _ = False


-- EXPRESSIONS 
-- Filter everything that can be a predicate constant
isPredConst (SExpr_predCon _ _ _ _) = True
isPredConst (SExpr_const _ _ predStatus _ _) = predStatus
isPredConst _ = False

-- Everything that can contain a predicate constant
hasPredConst (SExpr_predCon _ _ _ _) = True
hasPredConst (SExpr_const _ _ predStatus _ _) = predStatus
hasPredConst (SExpr_op  _ _ predStatus _) = predStatus 
hasPredConst _ = False


isVar (SExpr_var _ _) = True
isVar _              = False


-- Finds arity of a constant expression.
-- Arity given by the user takes precedance over inferred arity
instance HasArity (SExpr a) where 
    arity (SExpr_const _ _ _ given inferred) =
        case given of 
            Just n  -> Just n 
            Nothing -> Just inferred
    arity ( SExpr_predCon _ _ given inferred) =
        case given of 
            Just n  -> Just n 
            Nothing -> Just inferred
    arity (SExpr_op _ _ _ args) = Just $ length args      
    arity (SExpr_ann _ ex _) = arity ex
    -- Complex structures have no arity
    arity _ = Nothing

instance HasName (SExpr a) where 
    nameOf (SExpr_const   _ c _ _ _) = nameOf c
    nameOf (SExpr_var     _ v      ) = nameOf v
    nameOf (SExpr_predCon _ c _ _  ) = nameOf c
    nameOf (SExpr_app     _ ex' _  ) = nameOf ex'
    nameOf (SExpr_op      _ op _ _ ) = nameOf op
    nameOf (SExpr_number  _ n      ) = show n
    nameOf (SExpr_lam     _ _ _    ) = error "Name of lambda"
    nameOf (SExpr_list    _ _ _    ) = error "Name of list"
    nameOf (SExpr_ann     _ ex' _  ) = nameOf ex' 

-- Get a list of all subexpressions contained in an expression
-- WARNING: output includes variables bound by l-abstractions 
--          and defining lambda abstractions
instance Flatable (SExpr a) where
    --flatten ex@(SExpr_paren a ex') = ex : flatten ex'
    flatten ex@(SExpr_app _ func args) =
        ex : flatten func ++ ( concatMap flatten args)
    flatten ex@(SExpr_op _ _ _ args) =
        ex : (concatMap flatten args)
    flatten ex@(SExpr_lam _ vars bd) =
        ex : (map varToExpr vars) ++ (flatten bd)
        where varToExpr v@(Var a s)   = SExpr_var a v
              varToExpr v@(AnonVar a) = SExpr_var a v
    flatten ex@(SExpr_list _ initEls tl) =
        ex : ( concatMap flatten initEls) ++ 
            (case tl of 
                 Nothing -> [] 
                 Just ex -> flatten ex
            )
    --flatten ex@(SExpr_eq _ ex1 ex2) =
    --    ex : (flatten ex1) ++ (flatten ex2)
    flatten ex@(SExpr_ann _ ex' _) =
        ex : (flatten ex')
    flatten ex = [ex]  -- nothing else has subexpressions

-- Get/set information that expressions carry
getInfo (SExpr_const   a _ _ _ _  ) =  a
getInfo (SExpr_var     a _        ) =  a
getInfo (SExpr_number  a _        ) =  a
getInfo (SExpr_predCon a _ _ _    ) =  a
getInfo (SExpr_app     a _ _      ) =  a
getInfo (SExpr_op      a _ _ _    ) =  a
getInfo (SExpr_lam     a _ _      ) =  a
getInfo (SExpr_list    a _ _      ) =  a
getInfo (SExpr_ann     a _ _      ) =  a

setInfo inf (SExpr_const   _ b c d e) = SExpr_const   inf b c d e
setInfo inf (SExpr_var     _ b      ) = SExpr_var     inf b        
setInfo inf (SExpr_number  _ b      ) = SExpr_number  inf b        
setInfo inf (SExpr_predCon _ b c d  ) = SExpr_predCon inf b c d    
setInfo inf (SExpr_app     _ b c    ) = SExpr_app     inf b c      
setInfo inf (SExpr_op      _ b c d  ) = SExpr_op      inf b c d    
setInfo inf (SExpr_lam     _ b c    ) = SExpr_lam     inf b c      
setInfo inf (SExpr_list    _ b c    ) = SExpr_list    inf b c      
setInfo inf (SExpr_ann     _ b c    ) = SExpr_ann     inf b c      

-- Syntax constructs have type/location if it exists in the 
-- information they carry

instance HasType a => HasType (SExpr a) where
    typeOf e = typeOf (getInfo e)
    hasType tp e = let newInf = e |> getInfo |> hasType tp
                   in  setInfo newInf e

instance HasPosition a => HasPosition (SExpr a) where
    posSpan e = posSpan (getInfo e)


{-
 - Old stuff...
 -}


{-
-- A class describing all syntactic items carrying information
class HasInfo s where 
    getInfo :: s a -> a
    setInfo :: a -> s a -> s a

-- Constants, variables instances
instance HasInfo Const where 
    getInfo (Const a _ ) = a
    setInfo inf (Const _ c) = Const inf c

instance HasInfo Var where 
    getInfo (Var a _ )  = a
    getInfo (AnonVar a) = a
    setInfo inf (Var _ v) = Var inf v
    setInfo inf (AnonVar _) = AnonVar inf
-}

{-
instance (HasInfo s, HasType a) => HasType (s a) where
    typeOf synt = typeOf $ getInfo synt
   
    hasType tp synt = let newInf = synt |> getInfo |> hasType tp 
                      in  setInfo newInf synt

instance (HasInfo s, HasPosition a) => HasPosition (s a) where
    posSpan synt = posSpan $ getInfo synt
-}
{-
(SExpr_const   a b c d e) = SExpr_const   (hasType tp a) b c d e
    hasType tp (SExpr_var     a b      ) = SExpr_var     (hasType tp a) b        
    hasType tp (SExpr_number  a b      ) = SExpr_number  (hasType tp a) b        
    hasType tp (SExpr_predCon a b c d  ) = SExpr_predCon (hasType tp a) b c d    
    hasType tp (SExpr_app     a b c    ) = SExpr_app     (hasType tp a) b c      
    hasType tp (SExpr_op      a b c d  ) = SExpr_op      (hasType tp a) b c d    
    hasType tp (SExpr_lam     a b c    ) = SExpr_lam     (hasType tp a) b c      
    hasType tp (SExpr_list    a b c    ) = SExpr_list    (hasType tp a) b c      
    --hasType tp (SExpr_eq      a b c    ) = SExpr_eq      (hasType tp a) b c      
    hasType tp (SExpr_ann     a b c    ) = SExpr_ann     (hasType tp a) b c      
-}

{-
-- true and fail constants

sTrue :: a -> SExpr a
sTrue a = SExpr_const a 
                      (Const a "true")  
                      True
                      Nothing
                      (-1)
sFail :: a -> SExpr a
sFail a = SExpr_const a 
                      (Const a "fail")  
                      True
                      Nothing
                      (-1)

sCut :: a -> SExpr a
sCut a = SExpr_const a 
                     (Const a "!")  
                     True
                     Nothing
                     (-1)

sNil :: a -> SExpr a
sNil a = SExpr_const a 
                     (Const a "[]")  
                     False
                     Nothing
                     (-1)
-}

module ViperVM.Library.Maths.MatrixOps
   ( BasicOp (..)
   , BasicType (..)
   , clMapOpKernel
   )
where

import ViperVM.Library.Kernel

data BasicOp = OpAdd | OpSub | OpMul | OpDiv

data BasicType = TyUInt | TyInt | TyFloat | TyDouble

---------------------------------------------
-- ADDITION
---------------------------------------------

clMapOpKernel :: BasicType -> BasicOp -> Kernel
clMapOpKernel ty op = OpenCLSource code
   where
      tyS = case ty of
         TyUInt   -> "unsigned int"
         TyInt    -> "int"
         TyFloat  -> "float"
         TyDouble -> "double"
      opS = case op of
         OpAdd    -> "+"
         OpSub    -> "-"
         OpMul    -> "*"
         OpDiv    -> "/"

      code = 
         "__kernel void clMatrixBiOp\
         \  ( unsigned int w\
         \  , unsigned int h\
         \  , " ++ tyS ++ " *a\
         \  , " ++ tyS ++ " *b\
         \  , " ++ tyS ++ " *r\
         \) {\n\
         \  unsigned int x = get_global_id(0);\n\
         \  unsigned int y = get_global_id(1);\n\
         \  if (x < w && y < h) {\n\
         \     unsigned int k = x + y*w;\
         \     r[k] = a[k] " ++ opS ++ " b[k];\
         \  }\
         \}"

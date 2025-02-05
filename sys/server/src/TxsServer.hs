{-
TorXakis - Model Based Testing
Copyright (c) 2015-2017 TNO and Radboud University
See LICENSE at root directory of this repository.
-}

{-# LANGUAGE OverloadedStrings #-}

module Main

-- ----------------------------------------------------------------------------------------- --
--
--   Main Module TorXakis as a Socket Service
--
-- ----------------------------------------------------------------------------------------- --
-- export

(
  main      -- main :: IO ()
            -- torxakis server main
)

-- ----------------------------------------------------------------------------------------- --
-- import

where

import           Control.Concurrent
import           Control.DeepSeq
import           Control.Exception
import           Control.Monad.State
import qualified Data.Char           as Char
import qualified Data.Either         as Either
import qualified Data.List           as List
import qualified Data.Map            as Map
import qualified Data.Set            as Set
import qualified Data.String.Utils   as Utils
import qualified Data.Text           as T
import           Network.Socket  
import           Network.TextViaSockets  (listenOn) 
import           System.IO

-- import from local
import           CmdLineParser
import           ToProcdef
import qualified TxsServerConfig     as SC

-- import from serverenv
import qualified EnvServer           as IOS
import qualified IfServer            as IFS

-- import from core
import qualified BuildInfo
import qualified TxsCore
import qualified VersionInfo
import qualified EnvCore as IOC

-- import from defs
import qualified TxsDDefs
import qualified TxsDefs
import qualified TxsShow
import qualified Utils
import qualified VarId

-- import from bexpr
import qualified ProcId
import qualified ChanId

-- import from lpeops
import           ModelIdFactory

-- import from valexpr
import qualified Constant
import           Id
import qualified ValExpr

-- import from cnect
import qualified SocketWorld         as World

-- import from txs-compiler
import           TorXakis.Compiler

main :: IO ()
main = withSocketsDo $ do
  hSetBuffering stderr NoBuffering     -- alt: LineBuffering
  hSetBuffering stdout LineBuffering
  uConfig <- SC.loadConfig

  case SC.interpretConfig uConfig of
    Left xs -> do
      hPutStrLn stderr "Errors found while loading the configuration"
      hPrint stderr xs
    Right config -> do
      (portNr, sock) <- txsListenOn $ (clPortNumber . SC.cmdLineCfg) uConfig
      --(hs, host, _) <- accept sock
      (clientSock,clientAddr) <- accept sock
      (Just host, _) <- getNameInfo [] True False clientAddr -- args : [options] dolookuphost dolookupservice adress
      hs <- socketToHandle clientSock ReadWriteMode
      hSetBuffering hs LineBuffering
      hSetEncoding hs latin1
      hPutStrLn stderr "\nTXSSERVER >>  Starting  ..... \n"
      let initS = IOS.envsNone
              { IOS.host   = host
              , IOS.portNr = portNr
              , IOS.servhs = hs
              , IOS.params = SC.updateParamVals -- updating parameters...
                              (IOS.params IOS.envsNone) -- ...defined in ServerEnv
                              $ SC.configuredParameters config
              }
          coreConfig = config
      TxsCore.runTxsCore coreConfig cmdsIntpr initS
      threadDelay 1000000    -- 1 sec delay on closing
      close sock
      hPutStrLn stderr "\nTXSSERVER >>  Closing  ..... \n"

-- | Listen on the given port. If no port number is given, then a free port is
-- determined, and this port number is printed to the standard output.
txsListenOn :: Maybe PortNumber -> IO (PortNumber, Socket)
txsListenOn Nothing = do -- Get a free port to listen to.
    sock <- listenOn defaultPort
    portNr <- socketPort sock
    -- If no port was specified, then we print the port number in case the
    -- process that is starting 'txsserver' (most likely the 'torxakis'
    -- command) needs the port number to connect to it afterwards.
    print portNr
    return (portNr, sock)
txsListenOn (Just portNr) = do
    sock <- listenOn portNr
    return (portNr, sock)

-- * TorXakis server commands processing

cmdsIntpr :: IOS.IOS ()
cmdsIntpr = do
     modus      <- gets IOS.modus
     (cmd, args) <- IFS.getCmd
     case cmd of
-- ----------------------------------------------------------------------------------- modus --
       "START"     |       IOS.isNoned    modus ->  cmdStart     args
       "START"     | not $ IOS.isNoned    modus ->  cmdNoop      cmd
       "QUIT"                                   ->  cmdQuit      args
       "INIT"      |       IOS.isIdled    modus ->  cmdInit      args
       "INIT"      | not $ IOS.isIdled    modus ->  cmdNoop      cmd
       "TERMIT"    |       IOS.isGtIdled  modus ->  cmdTermit    args
       "TERMIT"    | not $ IOS.isGtIdled  modus ->  cmdNoop      cmd
       "STOP"      |       IOS.isGtInited modus ->  cmdStop      args
       "STOP"      | not $ IOS.isGtInited modus ->  cmdNoop      cmd
-- -------------------------------------------------------------------------------- settings --
       "INFO"      |       IOS.isGtNoned  modus ->  cmdInfo      args
       "INFO"      | not $ IOS.isGtNoned  modus ->  cmdNoop      cmd
       "PARAM"     |       IOS.isGtNoned  modus ->  cmdParam     args
       "PARAM"     | not $ IOS.isGtNoned  modus ->  cmdNoop      cmd
       "SEED"      |       IOS.isGtNoned  modus ->  cmdSeed      args
       "SEED"      | not $ IOS.isGtNoned  modus ->  cmdNoop      cmd
-- ------------------------------------------------------------------------------------ data --
       "VAR"       |       IOS.isGtIdled  modus ->  cmdVar       args
       "VAR"       | not $ IOS.isGtIdled  modus ->  cmdNoop      cmd
       "VAL"       |       IOS.isGtIdled  modus ->  cmdVal       args
       "VAL"       | not $ IOS.isGtIdled  modus ->  cmdNoop      cmd
       "EVAL"      |       IOS.isGtIdled  modus ->  cmdEval      args
       "EVAL"      | not $ IOS.isGtIdled  modus ->  cmdNoop      cmd
       "SOLVE"     |       IOS.isGtIdled  modus ->  cmdSolve     args "sol"
       "SOLVE"     | not $ IOS.isGtIdled  modus ->  cmdNoop      cmd
       "UNISOLVE"  |       IOS.isGtIdled  modus ->  cmdSolve     args "uni"
       "UNISOLVE"  | not $ IOS.isGtIdled  modus ->  cmdNoop      cmd
       "RANSOLVE"  |       IOS.isGtIdled  modus ->  cmdSolve     args "ran"
       "RANSOLVE"  | not $ IOS.isGtIdled  modus ->  cmdNoop      cmd
-- ----- ------------------------------------------------------------------------------ exec --
       "TESTER"    |       IOS.isInited   modus ->  cmdTester    args
       "TESTER"    | not $ IOS.isInited   modus ->  cmdNoop      cmd
       "SIMULATOR" |       IOS.isInited   modus ->  cmdSimulator args
       "SIMULATOR" | not $ IOS.isInited   modus ->  cmdNoop      cmd
       "STEPPER"   |       IOS.isInited   modus ->  cmdStepper   args
       "STEPPER"   | not $ IOS.isInited   modus ->  cmdNoop      cmd
-- -------------------------------------------------------------------- test, simulate, step --
       "TEST"      |       IOS.isTested   modus ->  cmdTest      args
       "TEST"      | not $ IOS.isTested   modus ->  cmdNoop      cmd
       "SIM"       |       IOS.isSimuled  modus ->  cmdSim       args
       "SIM"       | not $ IOS.isSimuled  modus ->  cmdNoop      cmd
       "STEP"      |       IOS.isStepped  modus ->  cmdStep      args
       "STEP"      | not $ IOS.isStepped  modus ->  cmdNoop      cmd
-- ----------------------------------------------------------------------------- btree state --
       "SHOW"      |       IOS.isGtIdled  modus ->  cmdShow      args
       "SHOW"      | not $ IOS.isGtIdled  modus ->  cmdNoop      cmd
       "GOTO"      |       IOS.isGtInited modus ->  cmdGoTo      args
       "GOTO"      | not $ IOS.isGtInited modus ->  cmdNoop      cmd
       "PATH"      |       IOS.isGtInited modus ->  cmdPath      args
       "PATH"      | not $ IOS.isGtInited modus ->  cmdNoop      cmd
       "TRACE"     |       IOS.isGtInited modus ->  cmdTrace     args
       "TRACE"     | not $ IOS.isGtInited modus ->  cmdNoop      cmd
       "MENU"      |       IOS.isGtInited modus ->  cmdMenu      args
       "MENU"      | not $ IOS.isGtInited modus ->  cmdNoop      cmd
       "MAP"       |       IOS.isTested   modus ->  cmdMap       args
       "MAP"       |       IOS.isSimuled  modus ->  cmdMap       args
       "MAP"       |       IOS.isStepped  modus ->  cmdNoop      cmd
       "MAP"       | not $ IOS.isGtInited modus ->  cmdNoop      cmd
       "NCOMP"     |       IOS.isInited   modus ->  cmdNComp     args
       "NCOMP"     | not $ IOS.isInited   modus ->  cmdNoop      cmd
       "LPE"       |       IOS.isInited   modus ->  cmdLPE       args
       "LPE"       | not $ IOS.isInited   modus ->  cmdNoop      cmd
       "LPEOP"     |       IOS.isInited   modus ->  cmdLPEOp     args
       "LPEOP"     | not $ IOS.isInited   modus ->  cmdNoop      cmd
       "LPEQ"      |       IOS.isInited   modus ->  cmdLPEQ      args
       "LPEQ"      | not $ IOS.isInited   modus ->  cmdNoop      cmd
       "MERGE"     |       IOS.isInited   modus ->  cmdMerge     args
       "MERGE"     | not $ IOS.isInited   modus ->  cmdNoop      cmd
       _                                        ->  cmdUnknown   cmd

-- ----------------------------------------------------------------------------------------- --
-- torxakis server individual command processing

-- ----------------------------------------------------------------------------------------- --

cmdNoop :: String -> IOS.IOS ()
cmdNoop cmd = do
     IFS.nack cmd [ "NoOp : No action"]
     cmdsIntpr

-- ----------------------------------------------------------------------------------------- --

cmdUnknown :: String -> IOS.IOS ()
cmdUnknown cmd = do
     IFS.nack "ERROR" [ "Unknown command : " ++ cmd ]
     cmdsIntpr

-- ----------------------------------------------------------------------------------------- --

cmdStart :: String -> IOS.IOS ()
cmdStart _ = do
     modify $ \env -> env { IOS.modus = IOS.Idled }
     host <- gets IOS.host
     port <- gets IOS.portNr
     IFS.pack "START" ["txsserver starting:  " ++ show host ++ " : " ++ show port]
     cmdsIntpr

-- ----------------------------------------------------------------------------------------- --

cmdQuit :: String -> IOS.IOS ()
cmdQuit _ = do
     modify $ \env -> env { IOS.modus = IOS.Noned }
     host <- gets IOS.host
     port <- gets IOS.portNr
     IFS.pack "QUIT" ["txsserver closing  " ++ show host ++ " : " ++ show port]
     return ()

-- ----------------------------------------------------------------------------------------- --

cmdInit :: String -> IOS.IOS ()
cmdInit args = do
     servhs             <- gets IOS.servhs
     unid               <- gets IOS.uid
     tdefs              <- lift TxsCore.txsGetTDefs
     sigs               <- gets IOS.sigs
     srctxts            <- lift $ lift $ mapM readFile (read args :: [String])
     let srctxt          = List.intercalate "\n\n" srctxts
     ((unid',tdefs', sigs'),e) <- lift $ lift $ catch
                             ( let parsing = compileLegacy srctxt
                                in return $!! (parsing, "")
                             )
                             ( \e -> return ((unid, tdefs, sigs), show (e::ErrorCall)))
     if e /= ""
       then do IFS.nack "INIT" [e]
               cmdsIntpr
       else do modify $ \env -> env { IOS.modus  = IOS.Inited
                                    , IOS.uid    = unid'
                                    , IOS.sigs   = sigs'
                                    }
               lift $ TxsCore.txsInit tdefs' sigs' ( IFS.hmack servhs . map TxsShow.pshow )
               IFS.pack "INIT" ["input files parsed:", args]
               cmdsIntpr

-- ----------------------------------------------------------------------------------------- --

cmdTermit :: String -> IOS.IOS ()
cmdTermit _ = do
     modify $ \env -> env { IOS.modus  = IOS.Idled
                          , IOS.tow    = ( Nothing, Nothing, [] )
                          , IOS.frow   = ( Nothing, [],      [] )
                          }
     lift TxsCore.txsTermit
     IFS.pack "TERMIT" []
     cmdsIntpr

-- ----------------------------------------------------------------------------------------- --

cmdStop :: String -> IOS.IOS ()
cmdStop _ = do
     World.closeSockets
     -- modus <- gets IOS.modus
     -- if  IOS.isSimuled modus
       -- then do -- [(_,valsut)] <- IOS.getParams ["param_Sut_deltaTime"]
               -- [(_,valsim)] <- IOS.getParams ["param_Sim_deltaTime"]
               -- IOS.setParams [("param_Sut_deltaTime",valsut)]
               -- IOS.setParams [("param_Sim_deltaTime",valsim)]
     modify $ \env -> env { IOS.modus   = IOS.Inited
                          , IOS.tow     = ( Nothing, Nothing, [] )
                          , IOS.frow    = ( Nothing, [],      [] )
                          }
     lift TxsCore.txsStop
     IFS.pack "STOP" []
     cmdsIntpr
       -- else do modify $ \env -> env { IOS.modus   = IOS.Inited
                                    -- , IOS.tow     = ( Nothing, Nothing, [] )
                                    -- , IOS.frow    = ( Nothing, [],      [] )
                                    -- }
               -- lift TxsCore.txsStop
               -- IFS.pack "STOP" []
               -- cmdsIntpr

-- ----------------------------------------------------------------------------------------- --

cmdInfo :: String -> IOS.IOS ()
cmdInfo _ = do
     IFS.pack "INFO" [ "TorXakis version    : " ++ VersionInfo.version
                     , "Build time          : " ++ BuildInfo.buildTime
                     ]
     cmdsIntpr

-- ----------------------------------------------------------------------------------------- --

cmdParam :: String -> IOS.IOS ()
cmdParam args =
     case words args of
       []        -> do params1 <- lift TxsCore.txsGetParams
                       params2 <- IOS.getParams []
                       mapM_ IFS.mack [ [ nm ++ " = " ++ val ]
                                      | (nm,val) <- params1 ++ params2
                                      ]
                       IFS.pack "PARAM" []
                       cmdsIntpr
       [prm]     -> do params1 <- lift $ TxsCore.txsGetParam prm
                       params2 <- IOS.getParams [prm]
                       case params1++params2 of
                         []         -> IFS.nack "PARAM" [ "No parameter: " ++ prm ]
                         [(_,val)]  -> IFS.pack "PARAM" [ prm++" = "++val ]
                         _          -> IFS.nack "PARAM" [ "More parameters: " ++ prm ]
                       cmdsIntpr
       [prm,val] -> do params1 <- lift $ TxsCore.txsSetParam prm val
                       params2 <- IOS.setParams [(prm,val)]
                       case params1++params2 of
                         []         -> IFS.nack "PARAM" [ "No parameter: " ++ prm ]
                         [(_,val')] -> IFS.pack "PARAM" [ prm++" = "++val' ]
                         _          -> IFS.nack "PARAM" [ "More parameters: " ++ prm ]
                       cmdsIntpr
       _         -> do IFS.nack "PARAM" [ "Unknown parameter action" ]
                       cmdsIntpr

-- ----------------------------------------------------------------------------------------- --

cmdSeed :: String -> IOS.IOS ()
cmdSeed args =
     case words args of
       [val] -> let seed :: Int
                    seed = read val
                  in do
                   lift $ TxsCore.txsSetSeed seed
                   IFS.pack "SEED" []
                   cmdsIntpr
       _     -> do IFS.nack "SEED" [ "Incorrect seed" ]
                   cmdsIntpr

-- ----------------------------------------------------------------------------------------- --

cmdVar :: String -> IOS.IOS ()
cmdVar args = do
     env              <- get
     let uid          = IOS.uid env
         sigs         = IOS.sigs env
         vars         = IOS.locvars env
         vals         = IOS.locvals env
     if  args == ""
       then do
         IFS.pack "VAR" [ TxsShow.fshow vars ]
         cmdsIntpr
       else do

         ((uid',vars'),e) <- lift $ lift $ catch
                               ( let p = compileUnsafe $
                                         compileVarDecls sigs (_id uid + 1) args
                                  in return $!! (p,"")
                               )
                               ( \e -> return ((uid,[]),show (e::ErrorCall)))

         if  e /= ""
           then do
             modify $ \env' -> env' { IOS.uid = uid' }
             IFS.nack "VAR" [ e ]
             cmdsIntpr
           else
             if  let newnames = map VarId.name vars'
                  in null ( newnames `List.intersect` map VarId.name vars ) &&
                     null ( newnames `List.intersect` map VarId.name (Map.keys vals))
               then do
                 modify $ \env' -> env' { IOS.locvars = vars ++ vars'
                                        , IOS.uid  = uid'
                                        }
                 IFS.pack "VAR" [ TxsShow.fshow vars' ]
                 cmdsIntpr
               else do
                 modify $ \env' -> env' { IOS.uid = uid' }
                 IFS.nack "VAR" [ "double variable names: " ++ TxsShow.fshow vars' ]
                 cmdsIntpr

-- ----------------------------------------------------------------------------------------- --

cmdVal :: String -> IOS.IOS ()
cmdVal args = do
     env              <- get
     let uid          = IOS.uid env
         sigs         = IOS.sigs env
         vars         = IOS.locvars env
         vals         = IOS.locvals env
     if  args == ""
       then do
         IFS.pack "VAL" [ TxsShow.fshow vals ]
         cmdsIntpr
       else do

         ((uid',venv'),e) <- lift $ lift $ catch
                               ( let p = compileUnsafe $
                                         compileValDefs sigs [] (_id uid + 1) args
                                 in return $!! (p,"")
                               )
                               ( \e -> return ((uid,Map.empty),show (e::ErrorCall)))

         if  e /= ""
           then do
             modify $ \env' -> env' { IOS.uid = uid' }
             IFS.nack "VAL" [ e ]
             cmdsIntpr
           else
             if let newnames = map VarId.name (Map.keys venv')
                 in null (newnames `List.intersect` map VarId.name vars) &&
                    null (newnames `List.intersect` map VarId.name (Map.keys vals))
               then do
                 modify $ \env' -> env' { IOS.locvals = vals `Map.union` venv'
                                        , IOS.uid     = uid'
                                        }
                 IFS.pack "VAL" [ TxsShow.fshow venv' ]
                 cmdsIntpr
               else do
                 modify $ \env' -> env' { IOS.uid = uid' }
                 IFS.nack "VAR" [ "double value names: " ++ TxsShow.fshow venv' ]
                 cmdsIntpr

-- ----------------------------------------------------------------------------------------- --

cmdEval :: String -> IOS.IOS ()
cmdEval args = do
     env              <- get
     let uid           = IOS.uid env
         sigs          = IOS.sigs env
         vals          = IOS.locvals env
         vars          = IOS.locvars env
     tdefs            <- lift TxsCore.txsGetTDefs

     ((uid',vexp'),e) <- lift $ lift $ catch
                           ( let (i,p) = compileUnsafe $
                                         compileValExpr sigs (Map.keys vals ++ vars) (_id uid + 1) args
                              in return $!! ((i, Just p),"")
                           )
                           ( \e -> return ((uid, Nothing),show (e::ErrorCall)))

     case vexp' of
       Just vexp'' -> do
                        modify $ \env' -> env' { IOS.uid = uid' }
                        mwalue <- lift $ TxsCore.txsEval (ValExpr.subst vals (TxsDefs.funcDefs tdefs) vexp'')
                        case mwalue of
                            Right walue -> do
                                            IFS.pack "EVAL" [ TxsShow.fshow walue ]
                                            cmdsIntpr
                            Left t      -> do
                                            IFS.nack "EVAL" [ "eval 2 - " ++ t ]
                                            cmdsIntpr

       Nothing -> do
                    modify $ \env' -> env' { IOS.uid = uid' }
                    IFS.nack "EVAL" [ "eval 1 - " ++ e ]
                    cmdsIntpr

-- ----------------------------------------------------------------------------------------- --

cmdSolve :: String -> String -> IOS.IOS ()
cmdSolve args kind = do
     let cmd :: String
         solver :: TxsCore.TxsSolveType
         (cmd,solver) = case kind of
                             "sol" -> ( "SOLVE"   , TxsCore.txsSolve    )
                             "uni" -> ( "UNISOLVE", TxsCore.txsUniSolve )
                             "ran" -> ( "RANSOLVE", TxsCore.txsRanSolve )
                             _     -> error $ "cmdSolve - Illegal kind : " ++ show kind
     env              <- get
     let uid           = IOS.uid env
         sigs          = IOS.sigs env
         vals          = IOS.locvals env
     tdefs            <- lift TxsCore.txsGetTDefs

     ((uid',vexp'),e) <- lift $ lift $ catch
                           ( let (i,p) = compileUnsafe $
                                         compileValExpr sigs [] (_id uid + 1) args
                              in return $!! ((i, Just p),"")
                           )
                           ( \e -> return ((uid, Nothing),show (e::ErrorCall)))

     case vexp' of
        Just vexp'' -> do
                        modify $ \env' -> env' { IOS.uid = uid' }
                        sols  <- lift $ solver (ValExpr.subst vals (TxsDefs.funcDefs tdefs) vexp'')
                        IFS.pack cmd [ show sols ]
                        cmdsIntpr
        Nothing  -> do
                        modify $ \env' -> env' { IOS.uid = uid' }
                        IFS.nack cmd [ e ]
                        cmdsIntpr

-- ----------------------------------------------------------------------------------------- --

cmdTester :: String -> IOS.IOS ()
cmdTester args = do
     envs'  <- get
     let Just (ioString,_) = Map.lookup "param_Sut_ioTime" (IOS.params envs')
         ioTime :: Int
         ioTime = read ioString
         Just (deltaString,_) = Map.lookup "param_Sut_deltaTime" (IOS.params envs')
         deltaTime :: Int
         deltaTime = read deltaString
     tdefs  <- lift TxsCore.txsGetTDefs
     case words args of
       [m,c] -> do
            let mdefs = [ mdef
                        | (TxsDefs.ModelId nm _, mdef) <- Map.toList (TxsDefs.modelDefs tdefs)
                        , T.unpack  nm == m
                        ]
                cdefs = [ cdef
                        | (TxsDefs.CnectId nm _, cdef) <- Map.toList (TxsDefs.cnectDefs tdefs)
                        , T.unpack nm == c
                        ]
            case (mdefs,cdefs) of
              ([modeldef],[cnectdef])
                         | isConsistentTester modeldef Nothing Nothing cnectdef
                -> do modify $ \env -> env { IOS.modus = IOS.Tested cnectdef }
                      World.openSockets
                      envs  <- get
                      lift $ TxsCore.txsSetTest (World.putSocket ioTime deltaTime envs) (World.getSocket deltaTime envs)
                                                modeldef Nothing Nothing
                      IFS.pack "TESTER" []
                      cmdsIntpr
              _ -> do IFS.nack "TESTER" [ "Wrong or inconsistent parameters" ]
                      cmdsIntpr
       [m,x,c] -> do
            let mdefs  =  [ mdef
                          | (TxsDefs.ModelId  nm _, mdef) <- Map.toList (TxsDefs.modelDefs tdefs)
                          , T.unpack nm == m
                          ]
                adefs  =  [ adef
                          | (TxsDefs.MapperId nm _, adef) <- Map.toList (TxsDefs.mapperDefs tdefs)
                          , T.unpack nm == x
                          ]
                pdefs  =  [ pdef
                          | (TxsDefs.PurpId   nm _, pdef) <- Map.toList (TxsDefs.purpDefs tdefs)
                          , T.unpack nm == x
                          ]
                cdefs  =  [ cdef
                          | (TxsDefs.CnectId  nm _, cdef) <- Map.toList (TxsDefs.cnectDefs tdefs)
                          , T.unpack nm == c
                          ]
            case (mdefs,adefs,pdefs,cdefs) of
              ([modeldef],[mapperdef],[],[cnectdef])
                         | isConsistentTester modeldef (Just mapperdef) Nothing cnectdef
                -> do modify $ \env -> env { IOS.modus  = IOS.Tested cnectdef }
                      World.openSockets
                      envs  <- get
                      lift $ TxsCore.txsSetTest (World.putSocket ioTime deltaTime envs) (World.getSocket deltaTime envs)
                                                modeldef (Just mapperdef) Nothing
                      IFS.pack "TESTER" []
                      cmdsIntpr
              ([modeldef],[],[purpdef],[cnectdef])
                         | isConsistentTester modeldef Nothing (Just purpdef) cnectdef
                -> do modify $ \env -> env { IOS.modus  = IOS.Tested cnectdef }
                      World.openSockets
                      envs  <- get
                      lift $ TxsCore.txsSetTest (World.putSocket ioTime deltaTime envs) (World.getSocket deltaTime envs)
                                                modeldef Nothing (Just purpdef)
                      IFS.pack "TESTER" [ ]
                      cmdsIntpr
              _ -> do IFS.nack "TESTER" [ "Wrong or inconsistent parameters" ]
                      cmdsIntpr
       [m,x,y,c] -> do
            let mdefs  =  [ mdef
                          | (TxsDefs.ModelId  nm _, mdef) <- Map.toList (TxsDefs.modelDefs tdefs)
                          , T.unpack nm == m
                          ]
                adefs  =  [ adef
                          | (TxsDefs.MapperId nm _, adef) <- Map.toList (TxsDefs.mapperDefs tdefs)
                          , T.unpack nm == x || T.unpack nm == y
                          ]
                pdefs  =  [ pdef
                          | (TxsDefs.PurpId   nm _, pdef) <- Map.toList (TxsDefs.purpDefs tdefs)
                          , T.unpack nm == x || T.unpack nm == y
                          ]
                cdefs  =  [ cdef
                          | (TxsDefs.CnectId  nm _, cdef) <- Map.toList (TxsDefs.cnectDefs tdefs)
                          , T.unpack nm == c
                          ]
            case (mdefs,adefs,pdefs,cdefs) of
              ([modeldef],[mapperdef],[purpdef],[cnectdef])
                         | isConsistentTester modeldef (Just mapperdef) (Just purpdef) cnectdef
                -> do modify $ \env -> env { IOS.modus  = IOS.Tested cnectdef }
                      World.openSockets
                      envs  <- get
                      lift $ TxsCore.txsSetTest (World.putSocket ioTime deltaTime envs) (World.getSocket deltaTime envs)
                                                modeldef (Just mapperdef) (Just purpdef)
                      IFS.pack "TESTER" [ ]
                      cmdsIntpr
              _ -> do IFS.nack "TESTER" [ "Wrong or inconsistent parameters" ]
                      cmdsIntpr
       _ -> do
            IFS.nack "TESTER" [ "Wrong parameters" ]
            cmdsIntpr

isConsistentTester :: TxsDefs.ModelDef ->
                      Maybe TxsDefs.MapperDef ->
                      Maybe TxsDefs.PurpDef ->
                      TxsDefs.CnectDef ->
                      Bool

isConsistentTester (TxsDefs.ModelDef minsyncs moutsyncs _ _)
                   Nothing
                   _
                   (TxsDefs.CnectDef _ conndefs)
 = let { mins   = Set.fromList minsyncs
         ; mouts  = Set.fromList moutsyncs
         ; ctows  = Set.fromList
                        [ Set.singleton chan | TxsDefs.ConnDtoW  chan _ _ _ _ <- conndefs ]
         ; cfrows = Set.fromList
                        [ Set.singleton chan | TxsDefs.ConnDfroW chan _ _ _ _ <- conndefs ]
         }
      in    mins   == ctows
         && cfrows == mouts

-- why aren't Model and Mapper checked for consistency?
isConsistentTester _
                   (Just (TxsDefs.MapperDef achins achouts asyncsets _))
                   _
                   (TxsDefs.CnectDef _ conndefs)
 = let { ctows  = Set.fromList
                        [ Set.singleton chan | TxsDefs.ConnDtoW  chan _ _ _ _ <- conndefs ]
         ; cfrows = Set.fromList
                        [ Set.singleton chan | TxsDefs.ConnDfroW chan _ _ _ _ <- conndefs ]
         ; ains   = Set.fromList $ filter (not . Set.null)
                        [ sync `Set.intersection` Set.fromList achins  | sync <- asyncsets ]
         ; aouts  = Set.fromList $ filter (not . Set.null)
                        [ sync `Set.intersection` Set.fromList achouts | sync <- asyncsets ]
         }
      in    cfrows `Set.isSubsetOf` ains
         && ctows  `Set.isSubsetOf` aouts

-- ----------------------------------------------------------------------------------------- --

cmdSimulator :: String -> IOS.IOS ()
cmdSimulator args = do
     envs'  <- get
     let Just (ioString,_) = Map.lookup "param_Sim_ioTime" (IOS.params envs')
         ioTime :: Int
         ioTime = read ioString
         Just (deltaString,_) = Map.lookup "param_Sim_deltaTime" (IOS.params envs')
         deltaTime :: Int
         deltaTime = read deltaString
     tdefs  <- lift TxsCore.txsGetTDefs
     case words args of
       [m,c] -> do
            let mdefs  =  [ mdef
                          | (TxsDefs.ModelId nm _, mdef) <- Map.toList (TxsDefs.modelDefs tdefs)
                          , T.unpack nm == m
                          ]
                cdefs  =  [ cdef
                          | (TxsDefs.CnectId nm _, cdef) <- Map.toList (TxsDefs.cnectDefs tdefs)
                          , T.unpack nm == c
                          ]
            case (mdefs,cdefs) of
              ([modeldef],[cnectdef])
                         | isConsistentSimulator modeldef Nothing cnectdef
                -> do modify $ \env -> env { IOS.modus = IOS.Simuled cnectdef }
                      World.openSockets
                      envs  <- get
                      lift $ TxsCore.txsSetSim (World.putSocket ioTime deltaTime envs) (World.getSocket deltaTime envs)
                                               modeldef Nothing
                      IFS.pack "SIMULATOR" []
                      cmdsIntpr
              _ -> do IFS.nack "SIMULATOR" [ "Wrong or inconsistent parameters" ]
                      cmdsIntpr
       [m,a,c] -> do
            let mdefs  =  [ mdef
                          | (TxsDefs.ModelId nm _, mdef) <- Map.toList (TxsDefs.modelDefs tdefs)
                          , T.unpack nm == m
                          ]
                adefs  =  [ adef
                          | (TxsDefs.MapperId nm _, adef) <- Map.toList (TxsDefs.mapperDefs tdefs)
                          , T.unpack nm == a
                          ]
                cdefs  =  [ cdef
                          | (TxsDefs.CnectId nm _, cdef) <- Map.toList (TxsDefs.cnectDefs tdefs)
                          , T.unpack nm == c
                          ]
            case (mdefs,adefs,cdefs) of
              ([modeldef],[mapperdef],[cnectdef])
                         | isConsistentSimulator modeldef (Just mapperdef) cnectdef
                -> do modify $ \env -> env { IOS.modus = IOS.Simuled cnectdef }
                      World.openSockets
                      envs  <- get
                      lift $ TxsCore.txsSetSim (World.putSocket ioTime deltaTime envs) (World.getSocket deltaTime envs)
                                               modeldef (Just mapperdef)
                      IFS.pack "SIMULATOR" []
                      cmdsIntpr
              _ -> do IFS.nack "SIMULATOR" [ "Wrong or inconsistent parameters" ]
                      cmdsIntpr
       _ -> error $ "cmdSimulator - Illegal arguments " ++ show args

isConsistentSimulator :: TxsDefs.ModelDef -> Maybe TxsDefs.MapperDef -> TxsDefs.CnectDef -> Bool

isConsistentSimulator (TxsDefs.ModelDef minsyncs moutsyncs _ _)
                      Nothing
                      (TxsDefs.CnectDef _ conndefs)
 = let { mins   = Set.fromList minsyncs
         ; mouts  = Set.fromList moutsyncs
         ; ctows  = Set.fromList
                        [ Set.singleton chan | TxsDefs.ConnDtoW  chan _ _ _ _ <- conndefs ]
         ; cfrows = Set.fromList
                        [ Set.singleton chan | TxsDefs.ConnDfroW chan _ _ _ _ <- conndefs ]
         }
      in    mins  == cfrows
         && mouts == ctows

isConsistentSimulator _
                      (Just (TxsDefs.MapperDef achins achouts asyncsets _))
                      (TxsDefs.CnectDef _ conndefs)
 = let { ctows  = Set.fromList
                        [ Set.singleton chan | TxsDefs.ConnDtoW  chan _ _ _ _ <- conndefs ]
         ; cfrows = Set.fromList
                        [ Set.singleton chan | TxsDefs.ConnDfroW chan _ _ _ _ <- conndefs ]
         ; ains   = Set.fromList $ filter (not . Set.null)
                        [ sync `Set.intersection` Set.fromList achins  | sync <- asyncsets ]
         ; aouts  = Set.fromList $ filter (not . Set.null)
                        [ sync `Set.intersection` Set.fromList achouts | sync <- asyncsets ]
         }
      in    cfrows `Set.isSubsetOf` ains
         && ctows  `Set.isSubsetOf` aouts


-- ----------------------------------------------------------------------------------------- --

cmdStepper :: String -> IOS.IOS ()
cmdStepper args = do
     tdefs  <- lift TxsCore.txsGetTDefs
     let mdefs   = TxsDefs.modelDefs tdefs
     case words args of
      [m] -> do
         let mdefs'  =  [ mdef
                        | (TxsDefs.ModelId nm _, mdef) <- Map.toList mdefs
                        , T.unpack nm == m
                        ]
         case mdefs' of
           [modeldef] -> do modify $ \env -> env { IOS.modus = IOS.Stepped }
                            lift $ TxsCore.txsSetStep modeldef
                            IFS.pack "STEPPER" []
                            cmdsIntpr
           _          -> do IFS.nack "STEPPER" [ "Wrong or inconsistent parameters" ]
                            cmdsIntpr
      _  -> do IFS.nack "STEPPER" [ "Not single argument" ]
               cmdsIntpr

-- ----------------------------------------------------------------------------------------- --

cmdTest :: String -> IOS.IOS ()
cmdTest args =
     case words args of
       []                                                             -- observe one output --
          -> do verdict <-lift TxsCore.txsTestOut
                IFS.pack "TEST" [TxsShow.fshow verdict]
                cmdsIntpr
       [d] | all Char.isDigit d                              -- d::int i/o test steps --
          -> do verdict <- lift $ TxsCore.txsTestN (read d)
                IFS.pack "TEST" [TxsShow.fshow verdict]
                cmdsIntpr
       _  -> do                                                 -- do given action as input --
                IOS.Tested (TxsDefs.CnectDef _ conndefs) <- gets IOS.modus
                let ctows  =  [ chan | TxsDefs.ConnDtoW  chan _ _ _ _ <- conndefs ]
                act <- readAction ctows args
                if  act == TxsDDefs.ActQui
                  then cmdsIntpr
                  else do verdict <- lift $ TxsCore.txsTestIn act
                          IFS.pack "TEST" [TxsShow.fshow verdict]
                          cmdsIntpr

-- ----------------------------------------------------------------------------------------- --

cmdSim :: String -> IOS.IOS ()
cmdSim args =
     case words args of
       []                                                           -- no arg: infinite sim --
         -> do verdict <- lift $ TxsCore.txsSimN (-1)
               IFS.pack "SIM" [TxsShow.fshow verdict]
               cmdsIntpr
       [d] | all Char.isDigit d                                   -- d::int sim steps --
         -> do verdict <- lift $ TxsCore.txsSimN (read d)
               IFS.pack "SIM" [TxsShow.fshow verdict]
               cmdsIntpr
       _                                                                -- not a valid call --
         -> do IFS.nack "SIM" ["wrong parameter"]
               cmdsIntpr

-- ----------------------------------------------------------------------------------------- --

cmdStep :: String -> IOS.IOS ()
cmdStep args =
     case words args of
       []                                                                -- no arg: one step --
         -> do verdict <- lift $ TxsCore.txsStepN 1
               IFS.pack "STEP" [TxsShow.fshow verdict]
               cmdsIntpr
       [d] | all Char.isDigit d                                       -- d::int steps --
         -> do verdict <- lift $ TxsCore.txsStepN (read d)
               IFS.pack "STEP" [TxsShow.fshow verdict]
               cmdsIntpr
       _                                                          -- action arg: step action --
         -> do tdefs    <- lift TxsCore.txsGetTDefs
               let mdefs = TxsDefs.modelDefs tdefs
                   chids = Set.toList $ Set.unions
                                        [ Set.unions (chins ++ chouts ++ spls)
                                        | (_, TxsDefs.ModelDef chins chouts spls _)
                                          <- Map.toList mdefs
                                        ]
               act <- readAction chids args
               if  act == TxsDDefs.ActQui
                 then cmdsIntpr
                 else do verdict <- lift $ TxsCore.txsStepA act
                         IFS.pack "STEP" [TxsShow.fshow verdict]
                         cmdsIntpr

-- ----------------------------------------------------------------------------------------- --

cmdShow :: String -> IOS.IOS ()
cmdShow args = do
     envs  <- get
     txt   <- case words args of
                ["tdefs"             ] -> lift $ TxsCore.txsShow "tdefs"     ""
                ["state"    ,"nr"    ] -> lift $ TxsCore.txsShow "state"     ""
                ["state"    ,"model" ] -> lift $ TxsCore.txsShow "model"     ""
                ["state"    ,"mapper"] -> lift $ TxsCore.txsShow "mapper"    ""
                ["state"    ,"purp"  ] -> lift $ TxsCore.txsShow "purp"      ""
                ["modeldef" ,nm      ] -> lift $ TxsCore.txsShow "modeldef"  nm
                ["mapperdef",nm      ] -> lift $ TxsCore.txsShow "mapperdef" nm
                ["purpdef"  ,nm      ] -> lift $ TxsCore.txsShow "purpdef"   nm
                ["procdef"  ,nm      ] -> lift $ TxsCore.txsShow "procdef"   nm
                ["funcdef"  ,nm      ] -> lift $ TxsCore.txsShow "funcdef"   nm
                ["cnect"             ] -> return $ let (_, _, towhdls ) = IOS.tow envs
                                                       (_, _, frowhdls) = IOS.frow envs
                                                    in TxsShow.fshow (towhdls ++ frowhdls)
                ["var"]     -> return $ TxsShow.fshow (IOS.locvars envs)
                ["val"]     -> return $ TxsShow.fshow (IOS.locvals envs)
                _           -> return ""
     case txt of
       "" -> do IFS.nack "SHOW" ["nothing to be shown"]
                cmdsIntpr
       s  -> do IFS.mack [s]
                IFS.pack "SHOW" ["\n"]
                cmdsIntpr

-- ----------------------------------------------------------------------------------------- --

cmdGoTo :: String -> IOS.IOS ()
cmdGoTo args =
     case words args of
       []        -> do IFS.pack "GOTO" ["gone to current state"]
                       cmdsIntpr
       ["back"]  -> do lift $ TxsCore.txsGoTo (-1)
                       IFS.pack "GOTO" ["gone to previous state"]
                       cmdsIntpr
       ["back", d] | all Char.isDigit d
                 -> let steps :: Int
                        steps = read d
                     in if  steps == 0
                          then do IFS.pack "GOTO" ["gone to current state"]
                                  cmdsIntpr
                          else do lift $ TxsCore.txsGoTo (-steps)
                                  IFS.pack "GOTO" ["gone back " ++ show steps ++ " states"]
                                  cmdsIntpr
       [d] | all Char.isDigit d
                 -> do lift $ TxsCore.txsGoTo (read d)
                       IFS.pack "GOTO" ["gone to state " ++ d]
                       cmdsIntpr
       _         -> do IFS.nack "GOTO" ["unknown state"]
                       cmdsIntpr

-- ----------------------------------------------------------------------------------------- --

cmdPath :: String -> IOS.IOS ()
cmdPath _ = do
     path <- lift TxsCore.txsPath
     IFS.mack [ TxsShow.showN n 6 ++ ": " ++ TxsShow.fshow s1 ++ " -> " ++
                unwords (lines $ TxsShow.fshow a) ++ " -> " ++ TxsShow.fshow s2
              | (n,(s1,a,s2)) <- zip [1 ..] path
              ]
     IFS.pack "PATH" ["\n"]
     cmdsIntpr

-- ----------------------------------------------------------------------------------------- --

cmdTrace :: String -> IOS.IOS ()
cmdTrace args = do
     path  <- lift TxsCore.txsPath
     let trace = [ a | (_, a ,_) <- path ]
     case words args of
       []       -> do IFS.mack [ TxsShow.showN n 6 ++ ":  " ++ TxsShow.fshow a
                               | (n, (_, a, _)) <- zip [1..] path
                               ]
                      IFS.pack "TRACE" ["\n"]
                      cmdsIntpr
       ["proc"] -> do IFS.mack [T.unpack (toProcdef trace)]
                      IFS.pack "TRACE" ["\n"]
                      cmdsIntpr
       ["purp"] -> do IFS.mack [T.unpack (toPurpdef trace)]
                      IFS.pack "TRACE" ["\n"]
                      cmdsIntpr
       _        -> do IFS.nack "TRACE" [ "No such trace format" ]
                      cmdsIntpr

-- ----------------------------------------------------------------------------------------- --

cmdMenu :: String -> IOS.IOS ()
cmdMenu args =
     let kind, what :: String
         (kind,what) =
          case words args of
              ["in"]       -> ( "mod", "in" )
              ["out"]      -> ( "mod", "out" )
              ["map"]      -> ( "map", "" )
              ["purp",gnm] -> ( "purp", gnm )
              _            -> ( "mod", "all" )
     in do
       menu <- lift $ TxsCore.txsMenu kind what
       IFS.mack [ TxsShow.fshow menu ]
       IFS.pack "MENU" [ "\n" ]
       cmdsIntpr

-- ----------------------------------------------------------------------------------------- --

cmdMap :: String -> IOS.IOS ()
cmdMap args = do
     tdefs      <- lift TxsCore.txsGetTDefs
     let mdefs   = TxsDefs.mapperDefs tdefs
         inchids = concat [ chins
                          | ( _ , TxsDefs.MapperDef chins _ _ _ ) <- Map.toList mdefs
                          ]
     if  null inchids
       then do IFS.nack "MAP" [ "No mapper(s) defined" ]
               cmdsIntpr
       else do act  <- readAction inchids args
               if  act == TxsDDefs.ActQui
               then do IFS.nack "MAP" [ "Not a valid action" ]
                       cmdsIntpr
               else do act' <- lift $ TxsCore.txsMapper act
                       IFS.pack "MAP" [TxsShow.fshow act']
                       cmdsIntpr

-- ----------------------------------------------------------------------------------------- --

cmdNComp :: String -> IOS.IOS ()
cmdNComp args = do
     tdefs <- lift TxsCore.txsGetTDefs
     case words args of
       [mname] -> case [ mdef
                       | (TxsDefs.ModelId nm _, mdef) <- Map.toList (TxsDefs.modelDefs tdefs)
                       , T.unpack nm == mname
                       ] of
                    [mdef]
                      -> do mayPurpId <- lift $ TxsCore.txsNComp mdef
                            case mayPurpId of
                              Just purpid
                                -> do IFS.pack "NCOMP" [ "Test Purpose generated: "
                                                          ++ TxsShow.fshow purpid ]
                                      cmdsIntpr
                              Nothing
                                -> do IFS.nack "NCOMP" [ "Could not generate test purpose" ]
                                      cmdsIntpr
                    _ -> do IFS.nack "NCOMP" [ "No such MODELDEF" ]
                            cmdsIntpr
       _       -> do IFS.nack "NCOMP" [ "Argument must be one MODELDEF name" ]
                     cmdsIntpr

-- ----------------------------------------------------------------------------------------- --

cmdLPE :: String -> IOS.IOS ()
cmdLPE args = do
     tdefs <- lift TxsCore.txsGetTDefs
     let mdefs = TxsDefs.modelDefs tdefs
         mids  = [ m | m@(TxsDefs.ModelId nm _uid, _) <- Map.toList mdefs
                           , T.unpack nm == args
                 ]
         chids = Set.toList $ Set.unions [ Set.unions (chins ++ chouts ++ spls)
                                         | (_, TxsDefs.ModelDef chins chouts spls _)
                                           <- Map.toList mdefs
                                         ]
     case mids of
       [ (_, TxsDefs.ModelDef chins chouts spls body) ]
         -> do -- Create a new model and process:
               -- - The new model instantiates the new process;
               -- - The new process uses the body of the old model.
               -- By doing this, LPEs can be generated for models that do not
               -- have a body that consists of only a process instantiation:
               newProcUnid <- lift IOC.newUnid
               let newProcId = TxsDefs.ProcId { ProcId.name = T.pack "proxyProcess"
                                              , ProcId.unid = newProcUnid
                                              , ProcId.procchans = map (ProcId.ChanSort . ChanId.chansorts) chids
                                              , ProcId.procvars = []
                                              , ProcId.procexit = ProcId.NoExit }
               let newProcDef = TxsDefs.ProcDef chids [] body
               let newProcInit = TxsDefs.procInst newProcId chids []
               newModelId <- lift $ getModelIdFromName "proxyModel"
               let newModelDef = TxsDefs.ModelDef chins chouts spls newProcInit
               let tdefs' = tdefs { TxsDefs.procDefs = Map.insert newProcId newProcDef (TxsDefs.procDefs tdefs)
                                  , TxsDefs.modelDefs = Map.insert newModelId newModelDef (TxsDefs.modelDefs tdefs)
                                  }
               lift $ IOC.modifyCS $ \st -> st { IOC.tdefs = tdefs' }
               -- Generate an LPE from the new model:
               mayModelId' <- lift $ TxsCore.txsLPE (Right newModelId)
               -- mayModelId' <- lift $ TxsCore.txsLPE (Right modelId)
               case mayModelId' of
                 Just (Right modelId') -> do IFS.pack "LPE" [ "LPE modeldef generated: "
                                                            , TxsShow.fshow modelId'
                                                            ]
                                             cmdsIntpr
                 _                     -> do IFS.nack "LPE" [ "Could not generate LPE" ]
                                             cmdsIntpr
       _ -> do bexpr       <- readBExpr chids args
               mayBexpr'   <- lift $ TxsCore.txsLPE (Left bexpr)
               case mayBexpr' of
                 Just (Left bexpr')    -> do IFS.pack "LPE" [ "LPE behaviour generated: "
                                                            , TxsShow.fshow bexpr'
                                                            ]
                                             cmdsIntpr
                 _                     -> do IFS.nack "LPE" [ "Could not generate LPE" ]
                                             cmdsIntpr

-- ----------------------------------------------------------------------------------------- --

cmdLPEQ :: String -> IOS.IOS ()
cmdLPEQ args = do
    let (inName, outName) = cutAfterSpace args
    msgs <- lift $ TxsCore.txsLPEQ inName outName
    IFS.pack "LPEQ" msgs
    cmdsIntpr
  where
    cutAfterSpace :: String -> (String, String)
    cutAfterSpace "" = ("", "")
    cutAfterSpace (' ':xs) = ("", xs)
    cutAfterSpace (x:xs) = let (s1, s2) = cutAfterSpace xs in (x:s1, s2)
-- cmdLPEQ

-- ----------------------------------------------------------------------------------------- --

cmdLPEOp :: String -> IOS.IOS ()
cmdLPEOp args = do
    let (opChain, namesAndInvariant) = cutAfterSpace args
    let (inName, outNameAndInvariant) = cutAfterSpace namesAndInvariant
    let (outName, invariantText) = cutAfterSpace outNameAndInvariant
    invariant <- readVExpr invariantText
    msgs <- lift $ TxsCore.txsLPEOp opChain inName outName invariant
    IFS.pack "LPEOP" msgs
    cmdsIntpr
  where
    cutAfterSpace :: String -> (String, String)
    cutAfterSpace "" = ("", "")
    cutAfterSpace (' ':xs) = ("", xs)
    cutAfterSpace (x:xs) = let (s1, s2) = cutAfterSpace xs in (x:s1, s2)
-- cmdLPEOp

-- ----------------------------------------------------------------------------------------- --

cmdMerge :: String -> IOS.IOS ()
cmdMerge args = do
    let (firstName, secondNameAndOutputName) = cutAfterSpace args
    let (secondName, outputName) = cutAfterSpace secondNameAndOutputName
    msgs <- lift $ TxsCore.txsMerge firstName secondName outputName
    IFS.pack "MERGE" msgs
    cmdsIntpr
  where
    cutAfterSpace :: String -> (String, String)
    cutAfterSpace "" = ("", "")
    cutAfterSpace (' ':xs) = ("", xs)
    cutAfterSpace (x:xs) = let (s1, s2) = cutAfterSpace xs in (x:s1, s2)
-- cmdMerge

-- Helper Functions
--
-- ----------------------------------------------------------------------------------------- --
-- readAction  :  read Action from String

readAction :: [TxsDefs.ChanId] -> String -> IOS.IOS TxsDDefs.Action
readAction chids args = do
     uid              <- gets IOS.uid
     sigs             <- gets IOS.sigs
     vals             <- gets IOS.locvals

     ((uid',offs'),e) <- lift $ lift $ catch
                           ( let p = compileUnsafe $
                                     compileOffer sigs chids (Map.keys vals) (_id uid + 1) args
                              in return $!! (p,"")
                           )
                           ( \e -> return ((uid,Set.empty),show (e::ErrorCall)))

     if  e /= ""
       then do IFS.nack "ERROR" [ "incorrect action: " ++ e ]
               return TxsDDefs.ActQui
       else do
         modify $ \env -> env { IOS.uid = uid' }
         let qstnoffs  =  [ q | q@TxsDefs.Quest{}
                                    <- concatMap TxsDefs.chanoffers (Set.toList offs') ]
         if  not $ null qstnoffs
           then do IFS.nack "ERROR" [ "incorrect action: no question mark offer allowed" ]
                   return TxsDDefs.ActQui
           else do
             pacts <- lift $ sequence
                            [ Utils.liftP2 (chid, sequence [ TxsCore.txsEval vexp
                                                           | TxsDefs.Exclam vexp <- choffs
                                                           ]
                                           )
                            | TxsDefs.Offer chid choffs <- Set.toList offs'
                            ]
             let eacts = map makeEither pacts
             case Either.partitionEithers eacts of
                ([], acts) -> return $ TxsDDefs.Act (Set.fromList acts)
                (es, _)    -> do
                                IFS.nack "ERROR" [ "eval failed:\n  " ++ Utils.join "\n  " es ]
                                return TxsDDefs.ActQui
    where
        makeEither :: (TxsDefs.ChanId, [Either String Constant.Constant]) -> Either String (TxsDefs.ChanId, [Constant.Constant])
        makeEither (chid, macts) =
             case Either.partitionEithers macts of
                ([], acts) -> Right (chid, acts)
                (es, _)    -> Left $ "eval failed:\n  " ++ Utils.join "\n  " es





-- ----------------------------------------------------------------------------------------- --
-- readBExpr :  read BExpr from String

readBExpr :: [TxsDefs.ChanId] -> String -> IOS.IOS TxsDefs.BExpr
readBExpr chids args = do
     uid               <- gets IOS.uid
     sigs              <- gets IOS.sigs
     vals              <- gets IOS.locvals

     ((_,bexpr'),e) <- lift $ lift $ catch
                            ( let p = compileUnsafe $
                                      compileBExpr sigs chids (Map.keys vals) (_id uid + 1) args
                               in return $!! (p,"")
                            )
                            ( \e -> return ((uid, TxsDefs.stop),show (e::ErrorCall)))

     if  e /= ""
       then do IFS.nack "ERROR" [ "incorrect behaviour expression: " ++ e ]
               return TxsDefs.stop
       else return bexpr'

-- ----------------------------------------------------------------------------------------- --
--                                                                                           --
-- ----------------------------------------------------------------------------------------- --

readVExpr :: String -> IOS.IOS TxsDefs.VExpr
readVExpr args =
     if args == ""
     then return (ValExpr.cstrConst (Constant.Cbool True))
     else do env              <- get
             let uid           = IOS.uid env
                 sigs          = IOS.sigs env
                 --vals          = IOS.locvals env
             --tdefs            <- lift TxsCore.txsGetTDefs

             ((_uid',vexp'),e) <- lift $ lift $ catch
                                   ( let (i,p) = compileUnsafe $
                                                 compileValExpr sigs [] (_id uid + 1) args
                                      in return $!! ((i, Just p),"")
                                   )
                                   ( \e -> return ((uid, Nothing),show (e::ErrorCall)))

             case vexp' of
              Just vexp'' -> return vexp''
              Nothing -> do IFS.nack "ERROR" [ "incorrect value expression: " ++ e ]
                            return (ValExpr.cstrConst (Constant.Cbool False))

-- ----------------------------------------------------------------------------------------- --
--                                                                                           --
-- ----------------------------------------------------------------------------------------- --

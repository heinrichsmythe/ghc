-----------------------------------------------------------------------------
--
-- Object-file symbols (called CLabel for histerical raisins).
--
-- (c) The University of Glasgow 2004
--
-----------------------------------------------------------------------------

module CLabel (
	CLabel,	-- abstract type

	mkClosureLabel,
	mkSRTLabel,
	mkSRTDescLabel,
	mkInfoTableLabel,
	mkEntryLabel,
	mkSlowEntryLabel,
	mkConEntryLabel,
	mkStaticConEntryLabel,
	mkRednCountsLabel,
	mkConInfoTableLabel,
	mkStaticInfoTableLabel,
	mkApEntryLabel,
	mkApInfoTableLabel,

	mkReturnPtLabel,
	mkReturnInfoLabel,
	mkAltLabel,
	mkDefaultLabel,
	mkBitmapLabel,

	mkClosureTblLabel,

	mkAsmTempLabel,

	mkModuleInitLabel,
	mkPlainModuleInitLabel,

	mkErrorStdEntryLabel,
	mkSplitMarkerLabel,
	mkUpdInfoLabel,
	mkSeqInfoLabel,
	mkIndStaticInfoLabel,
        mkMainCapabilityLabel,
	mkMAP_FROZEN_infoLabel,
        mkEMPTY_MVAR_infoLabel,

	mkTopTickyCtrLabel,
        mkCAFBlackHoleInfoTableLabel,
        mkSECAFBlackHoleInfoTableLabel,
	mkRtsPrimOpLabel,
	mkRtsSlowTickyCtrLabel,

	moduleRegdLabel,

	mkSelectorInfoLabel,
	mkSelectorEntryLabel,

	mkRtsInfoLabel,
	mkRtsEntryLabel,
	mkRtsRetInfoLabel,
	mkRtsRetLabel,
	mkRtsCodeLabel,
	mkRtsDataLabel,

	mkRtsInfoLabelFS,
	mkRtsEntryLabelFS,
	mkRtsRetInfoLabelFS,
	mkRtsRetLabelFS,
	mkRtsCodeLabelFS,
	mkRtsDataLabelFS,

	mkForeignLabel,

	mkCCLabel, mkCCSLabel,

	infoLblToEntryLbl, entryLblToInfoLbl,
	needsCDecl, isAsmTemp, externallyVisibleCLabel,
	CLabelType(..), labelType, labelDynamic, labelCouldBeDynamic,

	pprCLabel
    ) where


#include "HsVersions.h"
#include "../includes/ghcconfig.h"

import CmdLineOpts      ( opt_Static, opt_DoTickyProfiling )
import DataCon		( ConTag )
import Module		( moduleName, moduleNameFS, 
			  Module, isHomeModule )
import Name		( Name, isDllName, isExternalName )
import Unique		( pprUnique, Unique )
import PrimOp		( PrimOp )
import Config		( cLeadingUnderscore )
import CostCentre	( CostCentre, CostCentreStack )
import Outputable
import FastString


-- -----------------------------------------------------------------------------
-- The CLabel type

{-
CLabel is an abstract type that supports the following operations:

  - Pretty printing

  - In a C file, does it need to be declared before use?  (i.e. is it
    guaranteed to be already in scope in the places we need to refer to it?)

  - If it needs to be declared, what type (code or data) should it be
    declared to have?

  - Is it visible outside this object file or not?

  - Is it "dynamic" (see details below)

  - Eq and Ord, so that we can make sets of CLabels (currently only
    used in outputting C as far as I can tell, to avoid generating
    more than one declaration for any given label).

  - Converting an info table label into an entry label.
-}

data CLabel
  = IdLabel	    		-- A family of labels related to the
	Name			-- definition of a particular Id or Con
	IdLabelInfo

  | CaseLabel			-- A family of labels related to a particular
				-- case expression.
	{-# UNPACK #-} !Unique	-- Unique says which case expression
	CaseLabelInfo

  | AsmTempLabel 
	{-# UNPACK #-} !Unique

  | ModuleInitLabel 
	Module			-- the module name
	String			-- its "way"
	-- at some point we might want some kind of version number in
	-- the module init label, to guard against compiling modules in
	-- the wrong order.  We can't use the interface file version however,
	-- because we don't always recompile modules which depend on a module
	-- whose version has changed.

  | PlainModuleInitLabel Module	 -- without the vesrion & way info

  | ModuleRegdLabel

  | RtsLabel RtsLabelInfo

  | ForeignLabel FastString	-- a 'C' (or otherwise foreign) label
	(Maybe Int) 		-- possible '@n' suffix for stdcall functions
		-- When generating C, the '@n' suffix is omitted, but when
		-- generating assembler we must add it to the label.
	Bool			-- True <=> is dynamic

  | CC_Label  CostCentre
  | CCS_Label CostCentreStack

  deriving (Eq, Ord)


data IdLabelInfo
  = Closure		-- Label for closure
  | SRT                 -- Static reference table
  | SRTDesc             -- Static reference table descriptor
  | InfoTbl		-- Info tables for closures; always read-only
  | Entry		-- entry point
  | Slow		-- slow entry point

  | RednCounts		-- Label of place to keep Ticky-ticky  info for 
			-- this Id

  | Bitmap		-- A bitmap (function or case return)

  | ConEntry	  	-- constructor entry point
  | ConInfoTbl 		-- corresponding info table
  | StaticConEntry  	-- static constructor entry point
  | StaticInfoTbl   	-- corresponding info table

  | ClosureTable	-- table of closures for Enum tycons

  deriving (Eq, Ord)


data CaseLabelInfo
  = CaseReturnPt
  | CaseReturnInfo
  | CaseAlt ConTag
  | CaseDefault
  deriving (Eq, Ord)


data RtsLabelInfo
  = RtsShouldNeverHappenCode

  | RtsSelectorInfoTbl Bool{-updatable-} Int{-offset-}	-- Selector thunks
  | RtsSelectorEntry   Bool{-updatable-} Int{-offset-}

  | RtsApInfoTbl Bool{-updatable-} Int{-arity-}	        -- AP thunks
  | RtsApEntry   Bool{-updatable-} Int{-arity-}

  | RtsPrimOp PrimOp

  | RtsInfo       LitString	-- misc rts info tables
  | RtsEntry      LitString	-- misc rts entry points
  | RtsRetInfo    LitString	-- misc rts ret info tables
  | RtsRet        LitString	-- misc rts return points
  | RtsData       LitString	-- misc rts data bits, eg CHARLIKE_closure
  | RtsCode       LitString	-- misc rts code

  | RtsInfoFS     FastString	-- misc rts info tables
  | RtsEntryFS    FastString	-- misc rts entry points
  | RtsRetInfoFS  FastString	-- misc rts ret info tables
  | RtsRetFS      FastString	-- misc rts return points
  | RtsDataFS     FastString	-- misc rts data bits, eg CHARLIKE_closure
  | RtsCodeFS     FastString	-- misc rts code

  | RtsSlowTickyCtr String

  deriving (Eq, Ord)
	-- NOTE: Eq on LitString compares the pointer only, so this isn't
	-- a real equality.

-- -----------------------------------------------------------------------------
-- Constructing CLabels

mkClosureLabel	      	id 	= IdLabel id  Closure
mkSRTLabel		id 	= IdLabel id  SRT
mkSRTDescLabel		id 	= IdLabel id  SRTDesc
mkInfoTableLabel  	id 	= IdLabel id  InfoTbl
mkEntryLabel	      	id 	= IdLabel id  Entry
mkSlowEntryLabel      	id 	= IdLabel id  Slow
mkBitmapLabel   	id 	= IdLabel id  Bitmap
mkRednCountsLabel     	id 	= IdLabel id  RednCounts

mkConInfoTableLabel     con	= IdLabel con ConInfoTbl
mkConEntryLabel	      	con	= IdLabel con ConEntry
mkStaticInfoTableLabel  con	= IdLabel con StaticInfoTbl
mkStaticConEntryLabel 	con	= IdLabel con StaticConEntry

mkClosureTblLabel 	id	= IdLabel id ClosureTable

mkReturnPtLabel uniq		= CaseLabel uniq CaseReturnPt
mkReturnInfoLabel uniq		= CaseLabel uniq CaseReturnInfo
mkAltLabel      uniq tag	= CaseLabel uniq (CaseAlt tag)
mkDefaultLabel  uniq 		= CaseLabel uniq CaseDefault

mkAsmTempLabel 			= AsmTempLabel

mkModuleInitLabel		= ModuleInitLabel
mkPlainModuleInitLabel		= PlainModuleInitLabel

	-- Some fixed runtime system labels

mkErrorStdEntryLabel 		= RtsLabel RtsShouldNeverHappenCode
mkSplitMarkerLabel		= RtsLabel (RtsCode SLIT("__stg_split_marker"))
mkUpdInfoLabel			= RtsLabel (RtsInfo SLIT("stg_upd_frame"))
mkSeqInfoLabel			= RtsLabel (RtsInfo SLIT("stg_seq_frame"))
mkIndStaticInfoLabel		= RtsLabel (RtsInfo SLIT("stg_IND_STATIC"))
mkMainCapabilityLabel		= RtsLabel (RtsData SLIT("MainCapability"))
mkMAP_FROZEN_infoLabel		= RtsLabel (RtsInfo SLIT("stg_MUT_ARR_PTRS_FROZEN"))
mkEMPTY_MVAR_infoLabel		= RtsLabel (RtsInfo SLIT("stg_EMPTY_MVAR"))

mkTopTickyCtrLabel		= RtsLabel (RtsData SLIT("top_ct"))
mkCAFBlackHoleInfoTableLabel	= RtsLabel (RtsInfo SLIT("stg_CAF_BLACKHOLE"))
mkSECAFBlackHoleInfoTableLabel	= if opt_DoTickyProfiling then
                                    RtsLabel (RtsInfo SLIT("stg_SE_CAF_BLACKHOLE"))
                                  else  -- RTS won't have info table unless -ticky is on
                                    panic "mkSECAFBlackHoleInfoTableLabel requires -ticky"
mkRtsPrimOpLabel primop		= RtsLabel (RtsPrimOp primop)

moduleRegdLabel			= ModuleRegdLabel

mkSelectorInfoLabel  upd off	= RtsLabel (RtsSelectorInfoTbl upd off)
mkSelectorEntryLabel upd off	= RtsLabel (RtsSelectorEntry   upd off)

mkApInfoTableLabel  upd off	= RtsLabel (RtsApInfoTbl upd off)
mkApEntryLabel upd off		= RtsLabel (RtsApEntry   upd off)

	-- Foreign labels

mkForeignLabel :: FastString -> Maybe Int -> Bool -> CLabel
mkForeignLabel str mb_sz  is_dynamic = ForeignLabel str mb_sz is_dynamic

	-- Cost centres etc.

mkCCLabel	cc		= CC_Label cc
mkCCSLabel	ccs		= CCS_Label ccs

mkRtsInfoLabel      str = RtsLabel (RtsInfo      str)
mkRtsEntryLabel     str = RtsLabel (RtsEntry     str)
mkRtsRetInfoLabel   str = RtsLabel (RtsRetInfo   str)
mkRtsRetLabel       str = RtsLabel (RtsRet       str)
mkRtsCodeLabel      str = RtsLabel (RtsCode      str)
mkRtsDataLabel      str = RtsLabel (RtsData      str)

mkRtsInfoLabelFS    str = RtsLabel (RtsInfoFS    str)
mkRtsEntryLabelFS   str = RtsLabel (RtsEntryFS   str)
mkRtsRetInfoLabelFS str = RtsLabel (RtsRetInfoFS str)
mkRtsRetLabelFS     str = RtsLabel (RtsRetFS     str)
mkRtsCodeLabelFS    str = RtsLabel (RtsCodeFS    str)
mkRtsDataLabelFS    str = RtsLabel (RtsDataFS    str)

mkRtsSlowTickyCtrLabel :: String -> CLabel
mkRtsSlowTickyCtrLabel pat = RtsLabel (RtsSlowTickyCtr pat)

-- -----------------------------------------------------------------------------
-- Converting info labels to entry labels.

infoLblToEntryLbl :: CLabel -> CLabel 
infoLblToEntryLbl (IdLabel n InfoTbl) = IdLabel n Entry
infoLblToEntryLbl (IdLabel n ConInfoTbl) = IdLabel n ConEntry
infoLblToEntryLbl (IdLabel n StaticInfoTbl) = IdLabel n StaticConEntry
infoLblToEntryLbl (CaseLabel n CaseReturnInfo) = CaseLabel n CaseReturnPt
infoLblToEntryLbl (RtsLabel (RtsInfo s)) = RtsLabel (RtsEntry s)
infoLblToEntryLbl (RtsLabel (RtsRetInfo s)) = RtsLabel (RtsRet s)
infoLblToEntryLbl (RtsLabel (RtsInfoFS s)) = RtsLabel (RtsEntryFS s)
infoLblToEntryLbl (RtsLabel (RtsRetInfoFS s)) = RtsLabel (RtsRetFS s)
infoLblToEntryLbl _ = panic "CLabel.infoLblToEntryLbl"

entryLblToInfoLbl :: CLabel -> CLabel 
entryLblToInfoLbl (IdLabel n Entry) = IdLabel n InfoTbl
entryLblToInfoLbl (IdLabel n ConEntry) = IdLabel n ConInfoTbl
entryLblToInfoLbl (IdLabel n StaticConEntry) = IdLabel n StaticInfoTbl
entryLblToInfoLbl (CaseLabel n CaseReturnPt) = CaseLabel n CaseReturnInfo
entryLblToInfoLbl (RtsLabel (RtsEntry s)) = RtsLabel (RtsInfo s)
entryLblToInfoLbl (RtsLabel (RtsRet s)) = RtsLabel (RtsRetInfo s)
entryLblToInfoLbl (RtsLabel (RtsEntryFS s)) = RtsLabel (RtsInfoFS s)
entryLblToInfoLbl (RtsLabel (RtsRetFS s)) = RtsLabel (RtsRetInfoFS s)
entryLblToInfoLbl l = pprPanic "CLabel.entryLblToInfoLbl" (pprCLabel l)

-- -----------------------------------------------------------------------------
-- Does a CLabel need declaring before use or not?

needsCDecl :: CLabel -> Bool
  -- False <=> it's pre-declared; don't bother
  -- don't bother declaring SRT & Bitmap labels, we always make sure
  -- they are defined before use.
needsCDecl (IdLabel _ SRT)		= False
needsCDecl (IdLabel _ SRTDesc)		= False
needsCDecl (IdLabel _ Bitmap)		= False
needsCDecl (IdLabel _ _)		= True
needsCDecl (CaseLabel _ CaseReturnPt)	= True
needsCDecl (CaseLabel _ CaseReturnInfo)	= True
needsCDecl (ModuleInitLabel _ _)	= True
needsCDecl (PlainModuleInitLabel _)	= True
needsCDecl ModuleRegdLabel		= False

needsCDecl (CaseLabel _ _)		= False
needsCDecl (AsmTempLabel _)		= False
needsCDecl (RtsLabel _)			= False
needsCDecl (ForeignLabel _ _ _)		= False
needsCDecl (CC_Label _)			= True
needsCDecl (CCS_Label _)		= True

-- Whether the label is an assembler temporary:

isAsmTemp  :: CLabel -> Bool    -- is a local temporary for native code generation
isAsmTemp (AsmTempLabel _) = True
isAsmTemp _ 	    	   = False

-- -----------------------------------------------------------------------------
-- Is a CLabel visible outside this object file or not?

-- From the point of view of the code generator, a name is
-- externally visible if it has to be declared as exported
-- in the .o file's symbol table; that is, made non-static.

externallyVisibleCLabel :: CLabel -> Bool -- not C "static"
externallyVisibleCLabel (CaseLabel _ _)	   = False
externallyVisibleCLabel (AsmTempLabel _)   = False
externallyVisibleCLabel (ModuleInitLabel _ _)= True
externallyVisibleCLabel (PlainModuleInitLabel _)= True
externallyVisibleCLabel ModuleRegdLabel    = False
externallyVisibleCLabel (RtsLabel _)	   = True
externallyVisibleCLabel (ForeignLabel _ _ _) = True
externallyVisibleCLabel (IdLabel id _)     = isExternalName id
externallyVisibleCLabel (CC_Label _)	   = True
externallyVisibleCLabel (CCS_Label _)	   = True


-- -----------------------------------------------------------------------------
-- Finding the "type" of a CLabel 

-- For generating correct types in label declarations:

data CLabelType
  = CodeLabel
  | DataLabel

labelType :: CLabel -> CLabelType
labelType (RtsLabel (RtsSelectorInfoTbl _ _)) = DataLabel
labelType (RtsLabel (RtsApInfoTbl _ _))       = DataLabel
labelType (RtsLabel (RtsData _))              = DataLabel
labelType (RtsLabel (RtsCode _))              = CodeLabel
labelType (RtsLabel (RtsInfo _))              = DataLabel
labelType (RtsLabel (RtsEntry _))             = CodeLabel
labelType (RtsLabel (RtsRetInfo _))           = DataLabel
labelType (RtsLabel (RtsRet _))               = CodeLabel
labelType (RtsLabel (RtsDataFS _))            = DataLabel
labelType (RtsLabel (RtsCodeFS _))            = CodeLabel
labelType (RtsLabel (RtsInfoFS _))            = DataLabel
labelType (RtsLabel (RtsEntryFS _))           = CodeLabel
labelType (RtsLabel (RtsRetInfoFS _))         = DataLabel
labelType (RtsLabel (RtsRetFS _))             = CodeLabel
labelType (CaseLabel _ CaseReturnInfo)        = DataLabel
labelType (CaseLabel _ CaseReturnPt)	      = CodeLabel
labelType (ModuleInitLabel _ _)               = CodeLabel
labelType (PlainModuleInitLabel _)            = CodeLabel

labelType (IdLabel _ info) = 
  case info of
    InfoTbl    	  -> DataLabel
    Closure    	  -> DataLabel
    Bitmap     	  -> DataLabel
    ConInfoTbl 	  -> DataLabel
    StaticInfoTbl -> DataLabel
    ClosureTable  -> DataLabel
    _	          -> CodeLabel

labelType _        = DataLabel


-- -----------------------------------------------------------------------------
-- Does a CLabel need dynamic linkage?

-- When referring to data in code, we need to know whether
-- that data resides in a DLL or not. [Win32 only.]
-- @labelDynamic@ returns @True@ if the label is located
-- in a DLL, be it a data reference or not.

labelDynamic :: CLabel -> Bool
labelDynamic lbl = 
  case lbl of
   -- The special case for RtsShouldNeverHappenCode is because the associated address is
   -- NULL, i.e. not a DLL entry point
   RtsLabel RtsShouldNeverHappenCode -> False
   RtsLabel _  	     -> not opt_Static  -- i.e., is the RTS in a DLL or not?
   IdLabel n k       -> isDllName n
   ForeignLabel _ _ d  -> d
   ModuleInitLabel m _  -> (not opt_Static) && (not (isHomeModule m))
   PlainModuleInitLabel m -> (not opt_Static) && (not (isHomeModule m))
   _ 		     -> False

-- Basically the same as above, but this time for Darwin only.
-- The things that GHC does when labelDynamic returns true are not quite right
-- for Darwin. Also, every ForeignLabel might possibly be from a dynamic library,
-- and a 'false positive' doesn't really hurt on Darwin, so this just returns
-- True for every ForeignLabel.
--
-- ToDo: Clean up DLL-related code so we can do away with the distinction
--       between this and labelDynamic above.

labelCouldBeDynamic (ForeignLabel _ _ _) = True
labelCouldBeDynamic lbl = labelDynamic lbl

{-
OLD?: These GRAN functions are needed for spitting out GRAN_FETCH() at the
right places. It is used to detect when the abstractC statement of an
CCodeBlock actually contains the code for a slow entry point.  -- HWL

We need at least @Eq@ for @CLabels@, because we want to avoid
duplicate declarations in generating C (see @labelSeenTE@ in
@PprAbsC@).
-}

-----------------------------------------------------------------------------
-- Printing out CLabels.

{-
Convention:

      <name>_<type>

where <name> is <Module>_<name> for external names and <unique> for
internal names. <type> is one of the following:

	 info			Info table
	 srt			Static reference table
	 srtd			Static reference table descriptor
	 entry			Entry code (function, closure)
	 slow			Slow entry code (if any)
	 ret			Direct return address	 
	 vtbl			Vector table
	 <n>_alt		Case alternative (tag n)
	 dflt			Default case alternative
	 btm			Large bitmap vector
	 closure		Static closure
	 con_entry		Dynamic Constructor entry code
	 con_info		Dynamic Constructor info table
	 static_entry		Static Constructor entry code
	 static_info		Static Constructor info table
	 sel_info		Selector info table
	 sel_entry		Selector entry code
	 cc			Cost centre
	 ccs			Cost centre stack

Many of these distinctions are only for documentation reasons.  For
example, _ret is only distinguished from _entry to make it easy to
tell whether a code fragment is a return point or a closure/function
entry.
-}

pprCLabel :: CLabel -> SDoc

#if ! OMIT_NATIVE_CODEGEN
pprCLabel (AsmTempLabel u)
  =  getPprStyle $ \ sty ->
     if asmStyle sty then 
	ptext asmTempLabelPrefix <> pprUnique u
     else
	char '_' <> pprUnique u
#endif

pprCLabel lbl = 
#if ! OMIT_NATIVE_CODEGEN
    getPprStyle $ \ sty ->
    if asmStyle sty then 
	maybe_underscore (pprAsmCLbl lbl)
    else
#endif
       pprCLbl lbl

maybe_underscore doc
  | underscorePrefix = pp_cSEP <> doc
  | otherwise        = doc

-- In asm mode, we need to put the suffix on a stdcall ForeignLabel.
-- (The C compiler does this itself).
pprAsmCLbl (ForeignLabel fs (Just sz) _)
   = ftext fs <> char '@' <> int sz
pprAsmCLbl lbl
   = pprCLbl lbl

pprCLbl (CaseLabel u CaseReturnPt)
  = hcat [pprUnique u, ptext SLIT("_ret")]
pprCLbl (CaseLabel u CaseReturnInfo)
  = hcat [pprUnique u, ptext SLIT("_info")]
pprCLbl (CaseLabel u (CaseAlt tag))
  = hcat [pprUnique u, pp_cSEP, int tag, ptext SLIT("_alt")]
pprCLbl (CaseLabel u CaseDefault)
  = hcat [pprUnique u, ptext SLIT("_dflt")]

pprCLbl (RtsLabel RtsShouldNeverHappenCode) = ptext SLIT("0")
-- used to be stg_error_entry but Windows can't have DLL entry points as static
-- initialisers, and besides, this ShouldNeverHappen, right?

pprCLbl (RtsLabel (RtsCode str))   = ptext str
pprCLbl (RtsLabel (RtsData str))   = ptext str
pprCLbl (RtsLabel (RtsCodeFS str)) = ftext str
pprCLbl (RtsLabel (RtsDataFS str)) = ftext str

pprCLbl (RtsLabel (RtsSelectorInfoTbl upd_reqd offset))
  = hcat [ptext SLIT("stg_sel_"), text (show offset),
		ptext (if upd_reqd 
			then SLIT("_upd_info") 
			else SLIT("_noupd_info"))
	]

pprCLbl (RtsLabel (RtsSelectorEntry upd_reqd offset))
  = hcat [ptext SLIT("stg_sel_"), text (show offset),
		ptext (if upd_reqd 
			then SLIT("_upd_entry") 
			else SLIT("_noupd_entry"))
	]

pprCLbl (RtsLabel (RtsApInfoTbl upd_reqd arity))
  = hcat [ptext SLIT("stg_ap_"), text (show arity),
		ptext (if upd_reqd 
			then SLIT("_upd_info") 
			else SLIT("_noupd_info"))
	]

pprCLbl (RtsLabel (RtsApEntry upd_reqd arity))
  = hcat [ptext SLIT("stg_ap_"), text (show arity),
		ptext (if upd_reqd 
			then SLIT("_upd_entry") 
			else SLIT("_noupd_entry"))
	]

pprCLbl (RtsLabel (RtsInfo fs))
  = ptext fs <> ptext SLIT("_info")

pprCLbl (RtsLabel (RtsEntry fs))
  = ptext fs <> ptext SLIT("_entry")

pprCLbl (RtsLabel (RtsRetInfo fs))
  = ptext fs <> ptext SLIT("_info")

pprCLbl (RtsLabel (RtsRet fs))
  = ptext fs <> ptext SLIT("_ret")

pprCLbl (RtsLabel (RtsInfoFS fs))
  = ftext fs <> ptext SLIT("_info")

pprCLbl (RtsLabel (RtsEntryFS fs))
  = ftext fs <> ptext SLIT("_entry")

pprCLbl (RtsLabel (RtsRetInfoFS fs))
  = ftext fs <> ptext SLIT("_info")

pprCLbl (RtsLabel (RtsRetFS fs))
  = ftext fs <> ptext SLIT("_ret")

pprCLbl (RtsLabel (RtsPrimOp primop)) 
  = ppr primop <> ptext SLIT("_fast")

pprCLbl (RtsLabel (RtsSlowTickyCtr pat)) 
  = ptext SLIT("SLOW_CALL_") <> text pat <> ptext SLIT("_ctr")

pprCLbl ModuleRegdLabel
  = ptext SLIT("_module_registered")

pprCLbl (ForeignLabel str _ _)
  = ftext str

pprCLbl (IdLabel id  flavor) = ppr id <> ppIdFlavor flavor

pprCLbl (CC_Label cc) 		= ppr cc
pprCLbl (CCS_Label ccs) 	= ppr ccs

pprCLbl (ModuleInitLabel mod way)	
   = ptext SLIT("__stginit_") <> ftext (moduleNameFS (moduleName mod))
	<> char '_' <> text way
pprCLbl (PlainModuleInitLabel mod)	
   = ptext SLIT("__stginit_") <> ftext (moduleNameFS (moduleName mod))

ppIdFlavor :: IdLabelInfo -> SDoc
ppIdFlavor x = pp_cSEP <>
	       (case x of
		       Closure	    	-> ptext SLIT("closure")
		       SRT		-> ptext SLIT("srt")
		       SRTDesc		-> ptext SLIT("srtd")
		       InfoTbl    	-> ptext SLIT("info")
		       Entry	    	-> ptext SLIT("entry")
		       Slow	    	-> ptext SLIT("slow")
		       RednCounts	-> ptext SLIT("ct")
		       Bitmap		-> ptext SLIT("btm")
		       ConEntry	    	-> ptext SLIT("con_entry")
		       ConInfoTbl    	-> ptext SLIT("con_info")
		       StaticConEntry  	-> ptext SLIT("static_entry")
		       StaticInfoTbl 	-> ptext SLIT("static_info")
		       ClosureTable     -> ptext SLIT("closure_tbl")
		      )


pp_cSEP = char '_'

-- -----------------------------------------------------------------------------
-- Machine-dependent knowledge about labels.

underscorePrefix :: Bool   -- leading underscore on assembler labels?
underscorePrefix = (cLeadingUnderscore == "YES")

asmTempLabelPrefix :: LitString  -- for formatting labels
asmTempLabelPrefix =
#if alpha_TARGET_OS
     {- The alpha assembler likes temporary labels to look like $L123
	instead of L123.  (Don't toss the L, because then Lf28
	turns into $f28.)
     -}
     SLIT("$")
#elif darwin_TARGET_OS
     SLIT("L")
#else
     SLIT(".L")
#endif

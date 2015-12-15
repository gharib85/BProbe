(* ::Package:: *)

(*
	Copyright 2015 Lukas Schneiderbauer (lukas.schneiderbauer@gmail.com)


    This file is part of BProbe.

    BProbe is free software: you can redistribute it and/or modify
    it under the terms of the GNU General Public License as published by
    the Free Software Foundation, either version 3 of the License, or
    (at your option) any later version.

    BProbe is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
    GNU General Public License for more details.

    You should have received a copy of the GNU General Public License
    along with BProbe.  If not, see <http://www.gnu.org/licenses/>.

*)



BeginPackage["BProbe`"];

(* The sole PUBlIC API of this package *)
(* see the documentation for explanations *)
(***************************************************************************************)
	ProbeInit::usage = "";
	ProbeScan::usage = "";
	ProbeGetPointList::usage = "";
	ProbeReset::usage = "";
	ProbeGetMinEigenvalue::usage = "";
	ProbeGetEigenvalues::usage = "";
	ProbeGetState::usage = "";
	MatrixRepSU2::usage = "";
	MatrixRepSU3::usage = "";
(***************************************************************************************)
(* for usage messages: see the end of this package *)


Begin["`Private`"];
	Get[ "BProbe`Scan`" ];
	Get[ "BProbe`Gamma`" ];
	Get[ "BProbe`SU2Gen`" ];
	Get[ "BProbe`SU3Gen`" ];


	Options[ProbeInit] = Options[BProbe`Scan`init] ~Join~ {Probe -> "Laplace", Subspace -> Full};
	ProbeInit[t_?(VectorQ[#,MatrixQ]&), opts:OptionsPattern[]] := Block[{p,x,dim,n,gn,m,expr,eexpr,i,gamma,subspace},
		
		dim = Length[t];				(* dimension of target space *)
		n = Length[t[[1]]];				(* n times n matrices *)
		
		If[Not[ListQ[OptionValue[Subspace]]],
			subspace = Range[1, dim]; 			(* in this case, take the full space *)
		,
			subspace = OptionValue[Subspace];
		];
		
		p = Table[Unique["p"], {dim}];
		p[[Complement[Range[dim],subspace]]] = 0;
		
		
		(* build appropriate operator/matrix *)
		Switch[OptionValue[Probe],
		
		"Laplace",
			Print["Compiling Laplace Operator ..."];
		
			m = Sum[(IdentityMatrix[n] p[[i]] - t[[i]]).(IdentityMatrix[n] p[[i]] - t[[i]]), {i, 1, dim}];
			
			(* prepare for later *)
			x = Table[Unique["x"], n];
			eexpr = (Conjugate[x].#.x)& /@ t[[subspace]];
		
		,"Dirac",
			Print["Compiling Dirac Operator ..."];
			
			gamma = BProbe`Gamma`MatrixRepGamma[dim];
			m = Sum[KroneckerProduct[gamma[[i]], (t[[i]] - IdentityMatrix[n] p[[i]])], {i, 1, dim}];
			
			(* prepare for later *)
			gn = Length[gamma[[1]]];
			x = Table[Unique["x"], n*gn];
			eexpr = (Conjugate[x].KroneckerProduct[IdentityMatrix[gn],#].x)& /@ t[[subspace]];
			
		,"DiracSq",
			Print["Compiling square of Dirac Operator ..."];
			
			gamma = BProbe`Gamma`MatrixRepGamma[dim];
			m = Sum[KroneckerProduct[gamma[[i]], (t[[i]] - IdentityMatrix[n] p[[i]])], {i, 1, dim}];
			m = m.m;
			
			(* prepare for later *)
			gn = Length[gamma[[1]]];
			x = Table[Unique["x"], n*gn];
			eexpr = (Conjugate[x].KroneckerProduct[IdentityMatrix[gn],#].x)& /@ t[[subspace]];
			
		];
		
		
		(* compile the operator for (a lot) better performance *)
		expr = Simplify[ComplexExpand[m], Element[p, Reals]];
		cm = Compile @@ {DeleteCases[p,0], expr};
		func[y_] := Abs[Eigenvalues[cm @@ N[y], -1][[1]]];	(* define the function to be quasi-minimized *)
		
		(* compile expectation value of state *)
		Print["Compiling expectation-value function ..."];
		cexp = Compile @@ {Thread[{x, Table[_Complex, Length[x]]}], eexpr};
		expf[y_] := Block[{state},
			state = Eigenvectors[cm @@ N[y], -1][[1]];
			Return[Re[cexp @@ state]]; (* they should be real (always ?! todo) *)
		];

		BProbe`Scan`init[func, expf, DeleteCases[p,0], FilterRules[{opts}, Options[BProbe`Scan`init]]];

	];
	
	Options[ProbeReset] = Options[BProbe`Scan`reset];
	ProbeReset[opts:OptionsPattern[]] := Block[{},
		
		BProbe`Scan`reset[opts];
		
	];

	Options[ProbeScan] = Options[BProbe`Scan`start];
	ProbeScan[bdim_?IntegerQ /; bdim > 0, stepsize_?NumericQ /; stepsize > 0,
		opts:OptionsPattern[]
	] := Block[{result},
	
		result = BProbe`Scan`start[bdim, stepsize,
			FilterRules[{opts}, Options[BProbe`Scan`start]]
		];
		
		(*
		Return[result];
		*)
		(* forget about the result, it can be fetched with ProbeGetPointList[] anyway *)
		Return[];
	];
	
	ProbeGetPointList[] := Block[{},
		Return[BProbe`Scan`getlist[]];
	];
	
	ProbeGetMinEigenvalue[p_?(VectorQ[#,NumericQ]&)] := Block[{},
		Return[Abs[Eigenvalues[cm @@ N[p], -1][[1]]]];
	];
	
	ProbeGetEigenvalues[p_?(VectorQ[#,NumericQ]&)] := Block[{},
		Return[Eigenvalues[cm @@ N[p]]];
	];
	
	ProbeGetState[p_?(VectorQ[#,NumericQ]&)] := Block[{},
		Return[Eigensystem[cm @@ N[p],-1][[2,1]]];
	];
	
	MatrixRepSU2[n_?NumericQ /; n>0] := Block[{},
		Return[BProbe`SU2Gen`Private`MatrixRepSU2[n]];
	];
	
	MatrixRepSU3[list_?(VectorQ[#,NumericQ] &) /;
			Length[list]==2 &&
			list[[1]]>=0 &&
			list[[2]]>=0
	] := Block[{},
		Return[BProbe`SU3Gen`Private`MatrixRepSU3[list]];
	];


    (* formatting stuff for usage messages	*)
	(****************************************)
	
	link[name_] := ToString[Hyperlink[name, "file://" <> FileNameJoin[{$UserBaseDirectory, "Applications", "BProbe", "Documentation", name <> ".html"}]], StandardForm];
	link[name_, alias_] := ToString[Hyperlink[alias, "file://" <> FileNameJoin[{$UserBaseDirectory, "Applications", "BProbe", "Documentation", name <> ".html"}]], StandardForm];
	doc[name_] := ToString[Hyperlink[name, "paclet:ref/" <> name], StandardForm];
	italic[name_] := ToString[Style[name, Italic, Small], StandardForm];
	bold[name_] := ToString[Style[name, Bold], StandardForm];
	header[name_, args_] := Block[{i, str},
		str = link[name] <> "[";
		For[i=1,i<=Length[args],i++,
			str = str <> " _" <> doc[args[[i,1]]] <> " :: " <> italic[args[[i,2]]] <> " ";
			If[i<Length[args], str = str <> ","];
		];

		str = str <> "]";
		Return[str];
    ];
	(*										*)
	(****************************************)


End[];



(* The sole PUBlIC API of this package *)
(***************************************************************************************)
	ProbeInit::usage = BProbe`Private`header["ProbeInit", {{"List", "list of matrices"}}] <> " expects a list of d matrices. This method takes care of building the appropriate (Laplace-/Dirac-) operator for you which is needed to perform the rasterizing procedure. " <> BProbe`Private`bold["Note that calling this method is absolutely required before other methods of this package can be used!"] <> "."
	
	ProbeScan::usage = BProbe`Private`header["ProbeScan", {{"Integer", "dimension"}, {"Real", "step size"}}] <> " performs the actual scanning procedure. It implements an algorithm to rasterize the semi-classical limit of the brane configuration defined by a set of matrices as submanifold of the target space.";
	
	ProbeGetPointList::usage = BProbe`Private`header["ProbeGetPointList",{}] <> " returns a " <> BProbe`Private`doc["List"] <> " of already calculated points. A point is itself represented as a " <> BProbe`Private`doc["List"] <> " consisting of d " <> BProbe`Private`doc["Real"] <> "s.";
	
	ProbeReset::usage = BProbe`Private`header["ProbeReset",{}] <> " resets the package in a way, so that the command " <> BProbe`Private`header["ProbeScan", {{"Integer", "dimension"}, {"Real", "step size"}}] <> " starts a completely new calculation.";
	
	ProbeGetMinEigenvalue::usage = BProbe`Private`header["ProbeGetMinEigenvalue", {{"List", "point"}}] <> " returns the minimal eigenvalue (with respect to the modulus) of the (Laplace-/Dirac-) operator in question for a given point.";
	
	ProbeGetEigenvalues::usage = BProbe`Private`header["ProbeGetEigenvalues", {{"List", "point"}}] <> " returns the eigenvalues of the (Laplace-/Dirac-) operator in question for a given point.";
	
	ProbeGetState::usage = BProbe`Private`header["ProbeGetState", {{"List", "point"}}] <> " returns the eigenvector corresponding to the minimal eigenvalue (with respect to the modulus) of the (Laplace-/Dirac-) operator in question for a given point.";
	
	MatrixRepSU2::usage = BProbe`Private`header["MatrixRepSU2", {{"Integer", "dimension"}}] <> " returns a " <> BProbe`Private`doc["List"] <> " of three matrices, constituting a specific matrix representation of SU(2) acting on a representation space of the dimension given as argument."
	
	MatrixRepSU3::usage = BProbe`Private`header["MatrixRepSU3", {{"List", "highest_weight"}}] <> " returns a " <> BProbe`Private`doc["List"] <> " of eight matrices, constituting a specific matrix representation of SU(3) with highest weight given as argument."
(***************************************************************************************)

EndPackage[];

Print["Successfully loaded BProbe. See the " <> BProbe`Private`link["index", "documentation"] <> " for help."];

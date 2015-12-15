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



BeginPackage["BProbe`Scan`"];

	(* we don't need to expose this, since the user doesn't see it anyhow *)
	init::usage="init";
	start::usage="start";
	reset::usage="reset";
	getlist::usage="getlist";


Begin["`Private`"];

	Get["BProbe`Logger`"];
	Get["BProbe`Queue`"];


	Options[init] = {StartingPoint -> "min"}
	init[f_, exp_, x_, opts:OptionsPattern[]] :=
		Block[{s,f2},

			func = f;
			expvfunc = exp;

			If[!ListQ[OptionValue[StartingPoint]],

				Print["Look for global minimum ..."];
				f2[p__?NumericQ] := Abs[func[{p}]];
				s = NMinimize[f2 @@ x,x];
				startPoint = x /. s[[2]];
				
			,
				startPoint = OptionValue[StartingPoint];
			];
			
			reset[opts];

			Print["---"];

			Print["Minimum / Starting point:\n", func[startPoint], " at ", startPoint];
			Print["Gradient:\n", NGradient[func,startPoint]];
			Print["Abs Hess. Eigv:\n", Sort[Abs[#]&/@ Eigenvalues[NHessian[func,startPoint, Scale -> 0.01]]]];
			
			inited=True; (* say: okay, we did a initialization *)
		];


	Options[reset] = Options[init];
	reset[OptionsPattern[]] := Block[{},
		
			If[ListQ[OptionValue[StartingPoint]],
				startPoint = OptionValue[StartingPoint];
			]; 
		
			(* init stuff *)
			pointlist = {};
			AppendTo[pointlist, startPoint];
			boundary = new[Queue];
			boundary.push[{startPoint,startPoint}];
		
			rejectedCounterGrad = 0;
			rejectedCounterVal = 0;
			rejectedCounterRat = 0;
	];
	
	
	getlist[] := Return[pointlist];


	Options[start] = {MinimalSurface -> False}
	start[numberld_, ssize_, maxv_, maxevr_, gradtolf_, logfilename_, OptionsPattern[]] := 
		(* [number of directions, step size, tol factor for function value, ratio tol factor, tol factor for gradient, filename of log file] *)
		Block[{ppoint, cpoint, npoints, minpos, m, i},

			step = ssize;
			numberldirs = numberld;

			minsurf = OptionValue[MinimalSurface];
			maxevratio = maxevr;
			maxval = maxv;
			gradtolfactor = gradtolf;



			(* init call is necessary! *)
			If[inited==False,
				Message["First call Walk`init with appropriate parameters ... "];
				Abort[];
			];

			logger = new[Logger,logfilename];			


			cpoint = Last[pointlist];
			ppoint = Last[pointlist];


			(* CORE *)
			Monitor[Monitor[Monitor[Monitor[Monitor[
			While[boundary.size[] != 0,
				{ppoint, cpoint} = boundary.pop[];


				npoints = doStep[ppoint, cpoint];

				(* append new points, boundary info  + ppoints *)
				boundary.pushList[Thread[{
					Table[cpoint,{Length[npoints]}] ,
					npoints
				}]];
				pointlist = Join[pointlist, npoints];

				log[logger,
					"point accepted -" <> TextString[#]
				]& /@ npoints;

			];
			, "Points at boundary: " <> TextString[size[boundary]]]
			, "Rejected points (Gradient): " <> TextString[rejectedCounterGrad]]
			, "Rejected points (FuncValue): " <> TextString[rejectedCounterVal]]
			, "Rejected points (EVRatio): " <> TextString[rejectedCounterRat]]
			, "Added points: " <> TextString[Length[pointlist]]];


			close[logger];
			Return[pointlist];
		];


	doStep[ppoint_,cpoint_]:= (* [pastpoint, currentpoint] *)
		Block[{npoints,dirs},
		
			dirs = determineDirections[cpoint];
			
			npoints = (cpoint + #*step)& /@ dirs;
			npoints = manipulatePoints[ npoints ];
			npoints = filterPoints[ppoint, npoints];

			Return[npoints];
		];

		
		

(* PRIVATE METHODS (informal) *)

	determineDirections[point_]:= (* [point, tolerance] *)
		Block[{nhess, directions, processed},
			
			nhess = NHessian[func, point, Scale -> step/10];
			
			
			(* This should actually be checked in the "QValidDirection" method, but *)
			(* then the hessian would have to be recalculated.. so for performance reasons ... *)
			If[QEVRatioTooHigh[nhess],
				log[logger, "point rejected (evratiotoohigh) -" <> TextString[TextString[point]]];
				rejectedCounterRat += 1;
				
				Return[{}];
			];
			
			(* directions from Hessian *)
			directions = Eigensystem[nhess, -numberldirs][[2]];
			
			
			(* double them (forward, backward) *)
			processed = {};
			For[i=1, i<=Length[directions], i++,
				AppendTo[processed, directions[[i]]];
				AppendTo[processed, -directions[[i]]];
			];
			
			
			Return[processed];
		];


	manipulatePoints[npoints_] :=
		Block[{nnpoints, i, p, f2, s},
			
			nnpoints = npoints;
		
			(* if the surface is a minimum, we can apply *)
			(* FindMinimum to get a better approximation *)		
			If[minsurf,
			
				nnpoints = {};
			
				f2[p__?NumericQ] := func[{p}];
				p = Table[Unique["p"], {Length[npoints[[1]]]}];
				
				For[i=1, i<=Length[npoints], i++,
					
					Quiet[s = FindMinimum[f2 @@ p, Thread[{p,npoints[[i]]}]]];
					(* , MaxIterations->5 *)
					
					(* processed = ReplacePart[processed, i -> ((p /. s[[2]]) - point)]; *)
					AppendTo[nnpoints, (p /. s[[2]])];
				];
			];
			
			Return[nnpoints];
			
		];


	filterPoints[ppoint_,npoints_] := (* [pastpoint, newpoints] *)
		Block[{filtered, i},

			filtered = {};

			For[i=1, i<=Length[npoints], i++,

				If[QValidPoint[ppoint, npoints[[i]]],
					(* add *)
					AppendTo[filtered, npoints[[i]]];
				];

			];

			Return[filtered];
		];


	QValidPoint[ppoint_,npoint_]:= (* [pastpoint, newpoint] *)
		Block[{},

				If[Not[QBack[ppoint, npoint]],
					If[Not[QValueTooHigh[npoint]],
						If[Not[QGradientTooHigh[npoint]],
							If[Not[QNearPoints[npoint]],
								Return[True];
							,
								log[logger,
									"point rejected (nearpoints) -" <>
									TextString[npoint] <> "-" <> TextString[ppoint]];
							];
						,
							log[logger,
								"point rejected (gradienttoohigh) -" <>
								TextString[npoint] <> "-" <> TextString[ppoint]];
							rejectedCounterGrad += 1;
						];
					,
						log[logger,
							"point rejected (valuetoohigh) -" <>
							TextString[func[npoint]] <> "-" <> TextString[npoint] <> "-" <> TextString[ppoint]];
						rejectedCounterVal += 1;
					];
				,
					log[logger,
						"point rejected (back) -" <>
						TextString[npoint] <> "-" <> TextString[ppoint]];
				];

			(*otherwise*)
			Return[False];
		];


	QEVRatioTooHigh[nhess_] := (* [hesse matrix] *)
		Block[{evs, ratio},
		
		
			(* perform check only if evratio is finite *)
			If[maxevratio < \[Infinity],
		
				evs = Eigenvalues[nhess, -(numberldirs+1)];
				ratio = evs[[2]]/evs[[1]];
			
				If[ratio < maxevratio,
					Return[False];	
				,
					Return[True];
				];
			
			,
				Return[False];
			];
		
		];


	QGradientTooHigh[point_]:= (* [point] *)
		Block[{grad},
			
			(* perform check only if gradtolfactor is finite *)
			If[gradtolfactor < \[Infinity],
				
				grad = NGradient[func, point];
	
				If[Norm[grad] < gradtolfactor,
					Return[False];
				,
					Return[True];
				];
				
			,
				Return[False];
			];

		];


	QValueTooHigh[point_]:=
		Block[{},
			
			(* perform check only if maxval is finite *)
			If[maxval < \[Infinity],
				
				If[Abs[func[point]] < maxval,
					Return[False];
				,
					Return[True];
				];
			
			,
				Return[False];
			];
		];


	(* Are we going back again? *)
	QBack[ppoint_,npoint_]:= (* [pastpoint, newpoint] *)
		Block[{},

			(* TODO: check if this makes sense in all poss. configs *)

			If[Norm[npoint-ppoint] < step*0.7,
				Return[True];
			,(*else*)
				Return[False];
			];

		];


	QNearPoints[point_]:= (* [point] *)
		Block[{near},

			near = Nearest[pointlist,point][[1]];

			If[Norm[point-near] < step*0.7,
				Return[True];
			,
				Return[False];
			];

		];


Options[NHessian]={Scale->10^-3};
NHessian[f_,x_?(VectorQ[#,NumericQ]&),opts___?OptionQ] :=
	Block[{n,h,norm,z,mat,f0},
		n=Length[x];
		h=Scale /. {opts} /. Options[NHessian];
		norm=If[VectorQ[h],Outer[Times,2 h,2 h],4 h^2];
		z=If[VectorQ[h],DiagonalMatrix[h],h*IdentityMatrix[n]];
		mat=ConstantArray[0.,{n,n}];
		f0=f[x];
	
		Do[
			mat[[i,j]]=
				If[i==j,(*then*)
					.5 (f[x+2*z[[i]]]-2 f0+f[x-2*z[[i]]])
				, (*else*)
					f[x+z[[i]]+z[[j]]]-f[x+z[[i]]-z[[j]]]-f[x-z[[i]]+z[[j]]]+f[x-z[[i]]-z[[j]]]
				];
		,{i,n},{j,i,n}];
	
		Return[(mat+Transpose[mat])/norm];
];


NGradient[f_,x_?(VectorQ[#,NumericQ]&),opts___?OptionQ] :=
	Block[{n,h,norm,z,mat,f0},
		n=Length[x];
		h=Scale /. {opts} /. Options[NHessian];
		norm=If[VectorQ[h],Outer[Times,Sqrt[2 h],Sqrt[2 h]],2 h];
		z=If[VectorQ[h],DiagonalMatrix[h],h*IdentityMatrix[n]];
		mat=ConstantArray[0.,{n}];
		f0=f[x];

		Do[
			mat[[i]]= f[x-z[[i]]]-f[x+z[[i]]]
		,{i,n}];

	Return[mat/norm];
];


End[];
EndPackage[];

# FuseDMI: Manipulation-directed Bidirectional Live Programming for SVG

Building upon FuseDM proposed in paper `Fusing Direct Manipulations into Functional Programs` in POPL 2024, we further developed FuseDMI where ‘I’ stands for ‘Intentionally’.

![](./landing.png)

## How to run the system
- 1. compile elm to js, then serve `index.html`: 
    + compile by: `./compile.sh`
    + serve by web-server such as `http-server`
- 2. live running:  `elm reactor --port=8001`, default port is `8000`, which is also OK.
    + or run by : `./serve.sh`

## Benchmark Examples

All examples are under `src/Examples` folder, in addition, two step-by-step demos are under `src/Demos`.

## Experience Tour Guide 

  1. Open https://zanlyun.github.io/FuseDMI/ in a new tab.
  2. Copy one example code from `src/Examples` folder, or click on `New File` button, select `Bench-Battery`. It is important to note that for some other examples, the process includes additional building steps. However, to execute the code you have selected, you will need to remove any extra steps so that only one step remains in the code box.
   
```
main = 
let rect1_x= 119 in
let rect1_width= 178 in
let rect1_y= 146 in
let rect1_height= 76 in
let rect2_height= 48 in
let rect1_fill= 120 in
[ 
  rect {  0 
        , const rect1_fill
        , const rect1_x
        , const rect1_y
        , const rect1_width
        , const rect1_height}
, rect { 0
        , const rect1_fill
        , const (rect1_x+rect1_width)
        , const (rect1_y+(rect1_height-rect2_height)*0.5)
        , 26
        , const rect2_height}
];
```
1. Click the right arrow to generate SVG shown on the rightside.
2. Make a small change to SVG. For example, stretch the front of the battery horizentally.
3. Click the down arrow to see the generated delta:`modify 1 Graphic.map [id,id,id,id,+30,+-3]`
4. click the left arrow to fuse the delta into the program.

## A Simple Explanation of the Process 
0. Initially, the code box only has `main=[];`
1. Click on the `None` button, select one from `line`, `rect`, `circle`, `ellipse`, and `polygon`, and click `Draw` button
2. Draw on the canvas on the right.
3. Click the down arrow to generate delta
4. Click the left arrow to generate code.
5. Modify the code by direct change it, for example add `const` maker to proper constant or expression.
6. Draw again on the canvas and repeat the two click process to genrate delta and program.
7. Either select other shape and continue drawing.
8. ....

## Note
1. FuseDMI is implemented based on previous work FuseDM in `Fusing Direct Manipulations into Functional Programs` presented in POPL 2024, URL: https://dl.acm.org/doi/10.1145/3632883


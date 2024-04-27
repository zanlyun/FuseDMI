# FuseDMI: Manipulation-directed Bidirectional Live Programming for SVG

![](./landing.png)

## How to run the system
- 1. compile elm to js, then serve `index.html`: 
    + compile by: `./compile.sh`
    + serve by web-server such as `http-server`
- 2. live running:  `elm reactor --port=8001`, default port is `8000`, which is also OK.
    + or run by : `./serve.sh`

## Benchmark Examples

All examples are under `src/Examples` folder, in addition, two step-by-step demos are under `src/Demos`.

## User Guide 

  1. Open `https://zanlyun.github.io/FuseDMI/` in a new tab.
  2. Copy one example code from `src/Examples` folder. For example, the battery example at `src/Example/Bench-Battery.txt`.
   
```main = 
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
3. Click the right arrow to generate SVG shown on the rightside.
4. Make a small change to SVG. For example, stretch the front of the battery horizentally.
5. Click the down arrow to see the generated delta:`modify 1 Graphic.map [id,id,id,id,+30,+-3]`
6. click the left arrow to fuse the delta into the program.

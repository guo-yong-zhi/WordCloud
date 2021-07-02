using Colors
iter_expand(e) = Base.Iterators.repeated(e)
iter_expand(l::Vector) = Base.Iterators.cycle(l)
iter_expand(r::AbstractRange) = IterGen(st->rand(r))
iter_expand(t::Tuple) = IterGen(st->rand(t))
struct IterGen
    generator
end
Base.iterate(it::IterGen, state=0) = it.generator(state),state+1
Base.IteratorSize(it::IterGen) = Base.IsInfinite()

function displayschemes()
    for scheme in Render.schemes
        display(scheme)
        colors = Render.colorschemes[scheme].colors
        display(colors)
    end
end
function randomscheme()
    scheme = rand(Render.schemes)
    colors = Render.colorschemes[scheme].colors
    @show (scheme, length(colors))
    (colors...,)
end
function randommask(sz::Number=800; kargs...)
    s = sz * sz * (0.5+rand()/2)
    ratio = (0.5+rand()/2)
    ratio = ratio>0.9 ? 1.0 : ratio
    h = round(Int, sqrt(s*ratio))
    w = round(Int, h/ratio)
    randommask(w, h; kargs...)
end
function randommask(sz; kargs...)
    randommask(sz...; kargs...)
end
function randommask(w, h, args...; maskshape=:rand, kargs...)
    ran = Dict(box=>0.2, squircle=>0.7, ellipse=>1, :rand=>rand())[maskshape]
    if ran <= 0.2
        return randombox(w, h, args...; kargs...)
    elseif ran <= 0.7
        return randomsquircle(w, h, args...; kargs...)
    else
        return randomellipse(w, h, args...; kargs...)
    end
end
function randombox(w, h, r=:rand; kargs...)
    if r == :rand
        r = rand() * 0.5 - 0.05 # up to 0.45
        r = r < 0. ? 0. : r # 10% for 0.
        r = round(Int, h*r)
    end
    println("shape(box, $w, $h, $r", join([", $k=$(repr(v))" for (k,v) in kargs]), ")")
    return shape(box, w, h, r; kargs...)
end
function randomsquircle(w, h; rt=:rand, kargs...)
    if rt == :rand
        if rand()<0.8
            rt = rand()
        else
            ran = rand()
            if ran < 0.5
                rt = 2
            else
                rt = 1 + 1.5rand()
            end
        end
    end
    println("shape(squircle, $w, $h, rt=$rt", join([", $k=$(repr(v))" for (k,v) in kargs]), ")")
    return shape(squircle, w, h, rt=rt; kargs...)
end
function randomellipse(w, h; kargs...)
    println("shape(ellipse, $w, $h", join([", $k=$(repr(v))" for (k,v) in kargs]), ")")
    return shape(ellipse, w, h; kargs...)
end
function randomangles()
    a = rand((-1, 1)) .* rand((0, (0,90), (0,90,45), (0,90,45,-45), (0,45,-45), (45,-45), -90:90))
    println("angles = ", a)
    a
end
function randommaskcolor(colors)
    colors = parsecolor.(colors)
    try
        g = Gray.(colors)
        m = minimum(g)
        M = maximum(g)
        if sum(g)/length(g) < 0.7 && (m+M)/2 < 0.7 #明亮
            th1 = max(min(1.0, M+0.15), rand(0.85:0.001:1.0))
            th2 = min(1.0, th1+0.1)
            default = 1.0
        else    #黑暗
            th2 = min(max(0.0, m-0.15), rand(0.0:0.001:0.2)) #对深色不敏感，+0.05
            th1 = max(0.0, th2-0.15)
            default = 0.0
        end
        bgcolor = rand((default, (rand(th1:0.001:th2), rand(th1:0.001:th2), rand(th1:0.001:th2))))
        return bgcolor
    catch e
        @show e
        @show "colors sum failed",colors
        return "white"
    end
end
"""
load a img as mask, recolor, or resize, etc
## examples
* loadmask("res/heart.jpg")  
* loadmask("res/heart.jpg", 256, 256) #resize to 256*256  
* loadmask("res/heart.jpg", ratio=0.3) #scale 0.3  
* loadmask("res/heart.jpg", color="red", ratio=2) #set forecolor  
* loadmask("res/heart.jpg", transparentcolor=rgba->maximum(rgba[1:3])*(rgba[4]/255)>128) #set transparentcolor with a Function 
* loadmask("res/heart.jpg", color="red", transparentcolor=(1,1,1)) #set forecolor and transparentcolor  
"""
function loadmask(img::AbstractMatrix, args...; color=:original, backgroundcolor=:original, transparentcolor=:auto, kargs...)
    if color!=:original || backgroundcolor!=:original
        img = ARGB.(img)
        mask = backgroundmask(img, transparentcolor)
        if color!=:original
            color = parsecolor(color)
            m = @view img[mask]
            m .= convert.(eltype(img), Colors.alphacolor.(color, Colors.alpha.(m))) #保持透明度
        end
        if backgroundcolor!=:original
            backgroundcolor = parsecolor(backgroundcolor)
            m = @view img[.~mask]
            m .= convert.(eltype(img), Colors.alphacolor.(backgroundcolor, Colors.alpha.(m))) #保持透明度
        end
    end
    if !(isempty(args) && isempty(kargs))
        img = imresize(img, args...; kargs...)
    end
    println("mask size ", size(img))
    img
end
function loadmask(path, args...; kargs...)
    mask = Render.load(path)
    if issvg(mask)
        if !isempty(args) || !isempty(kargs) 
            @warn "edit svg file is not supported"
        end
        return mask
    end
    loadmask(mask,  args...; kargs...)
end

"like `paint` but export svg"
function paintsvg(wc::WC; background=true)
    if background == false || background === nothing
        sz = size(wc.mask)
    else
        if background == true
            background = getsvgmask(wc)
            if background === nothing
                @warn "embed bitmap into SVG. You can set `background=false` to remove background."
                background = getmask(wc)
            end
        end
        sz = size(wc.mask)
        nothing
    end
    Render.overlay(getsvgimages(wc), getpositions(wc), background=background, size=reverse(sz))
end
function paintsvg(wc::WC, file, args...; kargs...)
    img = paintsvg(wc, args...; kargs...)
    Render.save(file, img)
    img
end

"""
# examples
* paint(wc::WC)
* paint(wc::WC, background=false) #no background
* paint(wc::WC, background=outline(wc.mask)) #use a new background
* paint(wc::WC, ratio=0.5) #resize the result
* paint(wc::WC, "result.png", ratio=0.5) #save as png file, other bitmap formats may also work
* paint(wc::WC, "result.svg") #save as svg file
"""
function paint(wc::WC, args...; background=true, kargs...)
    if background == true
        background = wc.mask
    elseif background == false || background === nothing
        background = fill(ARGB32(1,1,1,0), size(wc.mask))
    end
    resultpic = convert.(ARGB32, background)#.|>ARGB32
    imgs = [convert.(ARGB32, i) for i in wc.imgs]
    overlay!(resultpic, imgs, getpositions(wc))
    if !(isempty(args) && isempty(kargs))
        resultpic = convert.(ARGB{Colors.N0f8}, resultpic)
        resultpic = imresize(resultpic, args...; kargs...)
    end
    resultpic
end

function paint(wc::WC, file, args...; kargs...)
    if endswith(file, r".svg|.SVG")
        img = paintsvg(wc, args...; kargs...)
    else
        img = paint(wc, args...; kargs...)
    end
    Render.save(file, img)
    img
end
        
function record(wc::WC, label::AbstractString, gif_callback=x->x)
#     @show size(n1)
    resultpic = overlay!(paint(wc), 
        rendertextoutlines(label, 32, color="black", linecolor="white", linewidth=1), 20, 20)
    gif_callback(resultpic)
end


runexample(example=:random) = @time evalfile(pkgdir(WordCloud)*"/examples/$(example).jl")
showexample(example=:random) = read(pkgdir(WordCloud)*"/examples/$(example).jl", String)|>print
examples = [e[1:prevind(e, end, 3)] for e in basename.(readdir(pkgdir(WordCloud)*"/examples")) if endswith(e, ".jl")]
@doc "Available values: [" * join(":".*examples, ", ") * "]" runexample
@doc "Available values: [" * join(":".*examples, ", ") * "]" showexample
function runexamples(examples=examples)
    println(length(examples), " examples: ", examples)
    for (i,e) in enumerate(examples)
        println("="^20, "\n# ",i,"/",length(examples), "\t", e, "\n", "="^20)
        runexample(e)
    end
end

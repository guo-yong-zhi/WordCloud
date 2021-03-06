mutable struct WC
    words
    weights
    imgs
    svgs
    mask
    svgmask
    qtrees
    maskqtree
    params::Dict{Symbol,Any}
end

"""
## Positional Arguments
Positional arguments are used to specify words and weights, and can be in different forms, such as Tuple or Dict, etc.
* words::AbstractVector{<:AbstractString}, weights::AbstractVector{<:Real}
* words_weights::Tuple
* counter::AbstractDict
* counter::AbstractVector{<:Pair}
## Optional Keyword Arguments
### style keyword arguments
* colors = "black" #all same color  
* colors = ("black", (0.5,0.5,0.7), "yellow", "#ff0000", 0.2) #choose entries randomly  
* colors = ["black", (0.5,0.5,0.7), "yellow", "red", (0.5,0.5,0.7), 0.2, ......] #use entries sequentially in cycle  
* colors = :seaborn_dark #using a preset scheme. see `WordCloud.colorschemes` for all supported Symbols. and `WordCloud.displayschemes()` may be helpful.
* angles = 0 #all same angle  
* angles = (0, 90, 45) #choose entries randomly  
* angles = 0:180 #choose entries randomly  
* angles = [0, 22, 4, 1, 100, 10, ......] #use entries sequentially in cycle  
* density = 0.55 #default 0.5  
* spacing = 1  #minimum spacing between words

### mask keyword arguments
* mask = loadmask("res/heart.jpg", 256, 256) #see doc of `loadmask`  
* mask = loadmask("res/heart.jpg", color="red", ratio=2) #see doc of `loadmask`  
* mask = shape(ellipse, 800, 600, color="white", backgroundcolor=(0,0,0,0)) #see doc of `shape`
* maskshape: `box`, `ellipse`, or `squircle`.  See `shape`. Take effect only when the `mask` argument is not given.
* masksize: Can be a tuple `(width, height)`, tuple `(width, height, cornerradius)` (for `box` only) or just a single number as hint. 
* backgroundsize: See `shape`. Take effect only when the `mask` argument is not given.
* maskcolor: like "black", "#ff0000", (0.5,0.5,0.7), 0.2, or :default, :original (keep it unchanged), :auto (auto recolor the mask).
* backgroundcolor: like "black", "#ff0000", (0.5,0.5,0.7), 0.2, or :default, :original, :maskcolor, :auto (random choose between :original and :maskcolor)
* outline, linecolor, smoothness: See function `shape` and `outline`. 
* transparent = (1,0,0) #set the transparent color in mask  
* transparent = nothing #no transparent color  
* transparent = c->(c[1]+c[2]+c[3])/3*(c[4]/255)>128) #set transparent with a Function. `c` is a (r,g,b,a) Tuple.
---NOTE
Some arguments depend on whether or not the `mask` is given or the type of the `mask` given.

### other keyword arguments
The keyword argument `run` is a function. It will be called after the `wordcloud` object constructed.
* run = placewords! #default setting, will initialize word's position
* run = generate! #get result directly
* run = initwords! #only initialize resources, such as rendering word images
* run = x->nothing #do nothing
---NOTE
* After getting the `wordcloud` object, these steps are needed to get the result picture: initwords! -> placewords! -> generate! -> paint
* You can skip `placewords!` and/or `initwords!`, and the default action will be performed
"""
wordcloud(wordsweights::Tuple; kargs...) = wordcloud(wordsweights...; kargs...)
wordcloud(counter::AbstractDict; kargs...) = wordcloud(keys(counter)|>collect, values(counter)|>collect; kargs...)
wordcloud(counter::AbstractVector{<:Union{Pair, Tuple, AbstractVector}}; kargs...) = wordcloud(first.(counter), [v[2] for v in counter]; kargs...)
wordcloud(text; kargs...) = wordcloud(processtext(text); kargs...)
function wordcloud(words::AbstractVector{<:AbstractString}, weights::AbstractVector{<:Real}; 
                colors=:auto, angles=:auto, 
                mask=:auto, font=:auto,
                transparent=:auto, minfontsize=:auto, maxfontsize=:auto, spacing=1, density=0.5,
                run=placewords!, kargs...)
    @assert length(words) == length(weights) > 0
    params = Dict{Symbol, Any}()
    colors, angles, mask, svgmask, font, transparent = getstylescheme(length(words); colors=colors, angles=angles, 
                                                    mask=mask, font=font, transparent=transparent, params=params, kargs...)
    params[:colors] = Any[colors...]
    params[:angles] = angles
    params[:transparent] = transparent
    mask, maskqtree, groundsize, maskoccupying = preparemask(mask, transparent)
    println("mask size ", size(mask))
    params[:groundsize] = groundsize
    params[:maskoccupying] = maskoccupying
    if maskoccupying == 0
        error("Have you set the right `transparent`? e.g. `transparent=mask[1,1]`")
    end
    @assert maskoccupying > 0
    if minfontsize==:auto
        minfontsize = min(8, sqrt(maskoccupying/length(words)/8))
        @show maskoccupying length(words)
    end
    if maxfontsize==:auto
        maxfontsize = minimum(size(mask)) / 2
    end
    println("set fontsize ∈ [$minfontsize, $maxfontsize]")
    params[:minfontsize] = minfontsize
    params[:maxfontsize] = maxfontsize
    params[:spacing] = spacing
    params[:density] = density
    params[:font] = font
    
    params[:state] = nameof(wordcloud)
    params[:epoch] = 0
    params[:indsmap] = nothing
    params[:custom] = Dict(:fontsize=>Dict(), :font=>Dict())
    params[:scale] = -1
    params[:wordids] = collect(1:length(words))
    l = length(words)
    wc = WC(copy(words), float.(weights), Vector(undef, l), Vector{SVGImageType}(undef, l), 
    mask, svgmask, Vector(undef, l), maskqtree, params)
    run(wc)
    wc
end
function getstylescheme(lengthwords; colors=:auto, angles=:auto, mask=:auto,
                masksize=:default, maskcolor=:default, 
                backgroundcolor=:default, padding=:default,
                outline=:default, linecolor=:auto, font=:auto,
                transparent=:auto, params=Dict{Symbol, Any}(), kargs...)
    merge!(params, kargs)
    colors = colors in DEFAULTSYMBOLS ? randomscheme() : colors
    angles = angles in DEFAULTSYMBOLS ? randomangles() : angles
    maskcolor0 = maskcolor
    backgroundcolor0 = backgroundcolor
    colors = colors isa Symbol ? (colorschemes[colors].colors..., ) : colors
    colors = Iterators.take(iter_expand(colors), lengthwords) |> collect
    angles = Iterators.take(iter_expand(angles), lengthwords) |> collect
    if mask == :auto
        if maskcolor in DEFAULTSYMBOLS
            if backgroundcolor in DEFAULTSYMBOLS || backgroundcolor == :maskcolor
                maskcolor = randommaskcolor(colors)
            else
                maskcolor = backgroundcolor
            end
        end
        masksize = masksize in DEFAULTSYMBOLS ? 40*√lengthwords : masksize
        if backgroundcolor in DEFAULTSYMBOLS
            backgroundcolor = maskcolor0 in DEFAULTSYMBOLS ? rand(((1,1,1,0), :maskcolor)) : (1, 1, 1, 0)
        end
        backgroundcolor == :maskcolor && @show backgroundcolor
        kg = []
        if outline in DEFAULTSYMBOLS
            if maskcolor0 in DEFAULTSYMBOLS && backgroundcolor0 in DEFAULTSYMBOLS
                outline = randomoutline()
            else
                outline = 0
            end
        end
        if linecolor in DEFAULTSYMBOLS && outline != 0
            linecolor = randomlinecolor(colors)
        end
        if outline != 0
            push!(kg, :outline=>outline)
            push!(kg, :linecolor=>linecolor)
        end
        padding = padding in DEFAULTSYMBOLS ? maximum(masksize)÷10 : padding
        mask = randommask(masksize, color=maskcolor; padding=padding, kg..., kargs...)
    else
        ms = masksize in DEFAULTSYMBOLS ? () : masksize
        if maskcolor == :auto && !issvg(loadmask(mask))
            maskcolor = randommaskcolor(colors)
            println("Recolor the mask with color $maskcolor.")
        end
        if backgroundcolor == :auto
            if maskcolor == :default
                backgroundcolor = randommaskcolor(colors)
                maskcolor = backgroundcolor
            else
                backgroundcolor = rand(((1,1,1,0), :maskcolor, :original))
            end
        end
        bc = backgroundcolor
        if backgroundcolor ∉ [:default, :original]
            @show backgroundcolor
            bc = (1,1,1,0) #to remove the original background in mask
        end
        if outline == :auto
            outline = randomoutline()
            outline != 0 && @show outline
        elseif outline in DEFAULTSYMBOLS
            outline = 0
        end
        if linecolor in DEFAULTSYMBOLS && outline != 0
            linecolor = randomlinecolor(colors)
        end
        padding = padding in DEFAULTSYMBOLS ? 0 : padding
        mask = loadmask(mask, ms...; color=maskcolor, transparent=transparent, backgroundcolor=bc, 
            outline=outline, linecolor=linecolor,padding=padding, kargs...)
    end
    if transparent == :auto
        if maskcolor ∉ DEFAULTSYMBOLS
            transparent = c->c!=WordCloud.torgba(maskcolor)
        end
    end
    params[:masksize] = masksize
    params[:maskcolor] = maskcolor
    params[:backgroundcolor] = backgroundcolor
    params[:outline] = outline
    params[:linecolor] = linecolor
    params[:padding] = padding
    svgmask = nothing
    if issvg(mask)
        svgmask = mask
        mask = svg2bitmap(mask)
        if maskcolor ∉ DEFAULTSYMBOLS && (:outline ∉ keys(params) || params[:outline] <= 0)
            Render.recolor!(mask, maskcolor) #svg2bitmap后有杂色 https://github.com/JuliaGraphics/Luxor.jl/issues/160
        end
    end
    font = font in DEFAULTSYMBOLS ? randomfont() : font
    colors, angles, mask, svgmask, font, transparent
end
Base.getindex(wc::WC, inds...) = wc.words[inds...]=>wc.weights[inds...]
Base.lastindex(wc::WC) = lastindex(wc.words)
Base.broadcastable(wc::WC) = Ref(wc)
getstate(wc::WC) = wc.params[:state]
setstate!(wc::WC, st::Symbol) = wc.params[:state] = st
function getindsmap(wc::WC)
    if wc.params[:indsmap] === nothing
        wc.params[:indsmap] = Dict(zip(wc.words, Iterators.countfrom(1)))
    end
    wc.params[:indsmap]
end
function index(wc::WC, w::AbstractString)
    getindsmap(wc)[w]
end
index(wc::WC, w::AbstractVector) = index.(wc, w)
index(wc::WC, i::Colon) = eachindex(wc.words)
index(wc::WC, i) = i
wordid(wc, i::Integer) = wc.params[:wordids][i]
wordid(wc, w) = wordid.(wc, index(wc, w))
getparameter(wc, args...) = getindex(wc.params, args...)
setparameter!(wc, args...) = setindex!(wc.params, args...)
hasparameter(wc, args...) = haskey(wc.params, args...)
getdoc = "The 1st arg is a wordcloud, the 2nd arg can be a word string(list) or a standard supported index and ignored to return all."
setdoc = "The 1st arg is a wordcloud, the 2nd arg can be a word string(list) or a standard supported index, the 3rd arg is the value to assign."
@doc getdoc getcolors(wc::WC, w=:) = wc.params[:colors][index(wc, w)]
@doc getdoc getangles(wc::WC, w=:) = wc.params[:angles][index(wc, w)]
@doc getdoc getwords(wc::WC, w=:) = wc.words[index(wc, w)]
@doc getdoc getweights(wc::WC, w=:) = wc.weights[index(wc, w)]
@doc setdoc setcolors!(wc::WC, w, c) = @view(wc.params[:colors][index(wc, w)]) .= parsecolor(c)
@doc setdoc setangles!(wc::WC, w, a::Union{Number, AbstractVector{<:Number}}) = @view(wc.params[:angles][index(wc, w)]) .= a
@doc setdoc 
function setwords!(wc::WC, w, v::Union{AbstractString, AbstractVector{<:AbstractString}})
    m = getindsmap(wc)
    @assert !any(v .∈ Ref(keys(m)))
    i = index(wc, w)
    Broadcast.broadcast((old,new)->m[new]=pop!(m,old), wc.words[i], v)
    @view(wc.words[i]) .= v
    v
end
@doc setdoc setweights!(wc::WC, w, v::Union{Number, AbstractVector{<:Number}}) = @view(wc.weights[index(wc, w)]) .= v
@doc getdoc getimages(wc::WC, w=:) = wc.imgs[index(wc, w)]
@doc getdoc getsvgimages(wc::WC, w=:) = wc.svgs[index(wc, w)]

@doc setdoc 
function setimages!(wc::WC, w, v::AbstractMatrix)
    @view(wc.imgs[index(wc, w)]) .= Ref(v)
    initqtree!(wc, w)
    v
end
setimages!(wc::WC, w, v::AbstractVector) = setimages!.(wc, index(wc,w), v)
@doc setdoc
function setsvgimages!(wc::WC, w, v)
    @view(wc.svgs[index(wc, w)]) .= v
    setimages!(wc::WC, w, svg2bitmap.(v))
end

@doc getdoc
function getfontsizes(wc::WC, w=:)
    inds = index(wc, w)
    ids = wordid(wc, inds)
    Broadcast.broadcast(inds, ids) do ind, id
        cf = wc.params[:custom][:fontsize]
        if id in keys(cf)
            return cf[id]
        else
            return clamp(getweights(wc, ind)*wc.params[:scale], wc.params[:minfontsize], wc.params[:maxfontsize])
        end
    end
end
@doc setdoc
function setfontsizes!(wc::WC, w, v::Union{Number, AbstractVector{<:Number}})
    push!.(Ref(wc.params[:custom][:fontsize]), wordid(wc, w) .=> v)
end
@doc getdoc
function getfonts(wc::WC, w=:)
    get.(Ref(wc.params[:custom][:font]), wordid(wc, w), wc.params[:font])
end
@doc setdoc
function setfonts!(wc::WC, w, v::Union{AbstractString, AbstractVector{<:AbstractString}})
    push!.(Ref(wc.params[:custom][:font]), wordid(wc, w) .=> v)
end
getmask(wc::WC) = wc.mask
getsvgmask(wc::WC) = wc.svgmask
getmaskcolor(wc::WC) = getparameter(wc, :maskcolor)
function getbackgroundcolor(wc::WC)
    c = getparameter(wc, :backgroundcolor)
    c = c == :maskcolor ? getmaskcolor(wc) : c
end
setbackgroundcolor!(wc::WC, v) = (setparameter!(wc, v, :backgroundcolor); v)
@doc getdoc * " Keyword argment `type` can be `getshift` or `getcenter`."
function getpositions(wc::WC, w=:; type=getshift)
    Stuffing.getpositions(wc.maskqtree, wc.qtrees, index(wc, w), type=type)
end

@doc setdoc * " Keyword argment `type` can be `setshift!` or `setcenter!`."
function setpositions!(wc::WC, w, x_y; type=setshift!)
    Stuffing.setpositions!(wc.maskqtree, wc.qtrees, index(wc, w), x_y, type=type)
end

Base.show(io::IO, m::MIME"image/png", wc::WC) = Base.show(io, m, paint(wc::WC))
Base.show(io::IO, m::MIME"image/svg+xml", wc::WC) = Base.show(io, m, paintsvg(wc::WC))
Base.show(io::IO, m::MIME"text/plain", wc::WC) = print(io, "wordcloud(", wc.words, ") #", length(wc.words), "words")
function Base.showable(::MIME"image/png", wc::WC)
    STATEIDS[getstate(wc)] >= STATEIDS[:initwords!] && showable("image/png", zeros(ARGB,(1,1)))
end
function Base.showable(::MIME"image/svg+xml", wc::WC)
    STATEIDS[getstate(wc)] >= STATEIDS[:initwords!] && (wc.svgmask !== nothing || !showable("image/png", wc))
end
Base.show(io::IO, wc::WC) = Base.show(io, "text/plain", wc)

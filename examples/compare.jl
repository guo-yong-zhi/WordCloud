#md# ### First generate the wordcloud on the left  
using WordCloud

stwords = ["us", "will"];
println("==Obama's==")
cs = WordCloud.randomscheme() #:Set1_8
as = WordCloud.randomangles() #(0,90,45,-45)
dens = 0.5 #not too high
wca = wordcloud(
    processtext(open(pkgdir(WordCloud)*"/res/Barack Obama's First Inaugural Address.txt"), stopwords=WordCloud.stopwords_en ∪ stwords), 
    colors = cs,
    angles = as,
    density = dens) |> generate!
#md# ### Then generate the wordcloud on the right      
println("==Trump's==")
wcb = wordcloud(
    processtext(open(pkgdir(WordCloud)*"/res/Donald Trump's Inaugural Address.txt"), stopwords=WordCloud.stopwords_en ∪ stwords),
    mask = getsvgmask(wca),
    colors = cs,
    angles = as,
    density = dens,
    run = x->nothing, #turn off the useless initimage! and placement! in advance
)
#md# Follow these steps to generate a wordcloud: initimage! -> placement! -> generate!
samewords = getwords(wca) ∩ getwords(wcb)
println(length(samewords), " same words")

for w in samewords
    setcolors!(wcb, w, getcolors(wca, w))
    setangles!(wcb, w, getangles(wca, w))
end
initimages!(wcb)

println("=ignore defferent words=")
keep(wcb, samewords) do
    @assert Set(wcb.words) == Set(samewords)
    centers = getpositions(wca, samewords, type=getcenter)
    setpositions!(wcb, samewords, centers, type=setcenter!) #manually initialize the position,
    setstate!(wcb, :placement!) #and set the state flag
    generate!(wcb, 1000, teleport=false, retry=1) #turn off the teleporting; retry=1 means no rescale
end

println("=pin same words=")
pin(wcb, samewords) do
    placement!(wcb)
    generate!(wcb, 1000, retry=1) #allow teleport but don‘t allow rescale
end

if getstate(wcb) != :generate!
    println("=overall tuning=")
    generate!(wcb, 1000, teleport=setdiff(getwords(wcb), samewords), retry=2) #only teleport the unique words
end

ma = paint(wca)
mb = paint(wcb)
h,w = size(ma)
space = fill(mb[1], (h, w÷20))
try mkdir("address_compare") catch end
println("results are saved in address_compare")
WordCloud.save("address_compare/compare.png", [ma space mb])
#eval# try rm("address_compare", force=true, recursive=true) catch end 
gif = WordCloud.GIF("address_compare")
record(wca, "Obama", gif)
record(wcb, "Trump", gif)
WordCloud.Render.generate(gif, framerate=1)
wca, wcb
#eval# runexample(:compare)
#md# ![](address_compare/compare.png)  
#md# ![](address_compare/result.gif)  

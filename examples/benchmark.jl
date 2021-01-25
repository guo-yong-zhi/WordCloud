using WordCloud
using Random

println("This test may take several minutes")

words = [Random.randstring(rand(1:8)) for i in 1:200]
weights = randexp(length(words)) .* 2000 .+ rand(20:100, length(words));
wc1 = wordcloud(words, weights, mask=shape(ellipse, 500, 500, color=0.15), angles=(0,90,45), fillingrate=0.7)

words = [Random.randstring(rand(1:8)) for i in 1:500]
weights = randexp(length(words)) .* 2000 .+ rand(20:100, length(words));
wc2 = wordcloud(words, weights, mask=shape(ellipse, 500, 500, color=0.15), angles=(0,90,45))

words = [Random.randstring(rand(1:8)) for i in 1:5000]
weights = randexp(length(words)) .* 2000 .+ rand(20:100, length(words));
wc3 = wordcloud(words, weights, mask=shape(box, 2000, 2000, 100, color=0.15), angles=(0,90,45))

wcs = [wc1, wc1, wc2, wc3] #repeat wc1 to trigger compiling
ts = [WordCloud.trainepoch_E!,WordCloud.trainepoch_EM!,WordCloud.trainepoch_EM2!,WordCloud.trainepoch_EM3!,
        WordCloud.trainepoch_P!,WordCloud.trainepoch_P2!,WordCloud.trainepoch_level!]
for (i,wc) in enumerate(wcs)
    println("\n\n", "*"^10, "wordcloud - $(length(wc.words)) words on mask$(size(wc.mask))", "*"^10)
    for (j,t) in enumerate(ts)
        println("\n", i-1, "==== ", j, "/", length(ts), " ", nameof(t))
        placement!(wc)
        @time generate!(wc, trainer=t, retry=1)
    end
end

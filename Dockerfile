FROM erlang:27

ENV TZ=Europe/Kyiv

RUN apt-get update
RUN apt-get install git -y
RUN apt-get install curl -y
RUN apt-get install wget -y


## ============== ERLANG ==============

#RUN wget https://github.com/erlang/rebar3/releases/download/3.24.0/rebar3 && chmod +x rebar3 && mv rebar3 /usr/local/bin

#WORKDIR ~/Erlang/news_hub
#RUN rebar3 as prod release
COPY _build/prod/rel/auth_hub/ /opt/auth_hub/


#WORKDIR ~/news_hub
#RUN rebar3 as prod release
#RUN mv _build/prod/rel/news_hub /sybase/news_hub-$VERSION


## ============== PYTHON ==============

#RUN pip3 install erlport
#RUN pip install pyTelegramBotAPI


## ============== RUN ==============

CMD ["/opt/auth_hub/bin/auth_hub", "foreground"]



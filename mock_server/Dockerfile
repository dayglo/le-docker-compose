FROM node:4.1.2
ENV payload={}
ENV MODE=stdout
ENV NODE_ENV=production
        
COPY . /usr/src/app/
WORKDIR /usr/src/app/

CMD [ "node", "runtestserver.js"]

EXPOSE 80

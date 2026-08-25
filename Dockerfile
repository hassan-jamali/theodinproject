# ruby base image
FROM ruby:3.4.6

# install system dependencies
RUN apt-get update -qq && apt-get install -y \
    build-essential \
    libpq-dev \
    nodejs \
    npm
RUN npm install --global yarn

# set workdir
WORKDIR /app

# copy dependency files
COPY Gemfile Gemfile.lock .ruby-version package.json yarn.lock ./

# install gems and node packages
RUN bundle install
RUN yarn install

# copy app code
COPY . .

# expose rails port
EXPOSE 3000

# default startup command
CMD ["bin/rails", "server", "-b", "0.0.0.0"]
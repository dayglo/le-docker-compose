docker build -t le-nginx:1.0.0 .
pushd mock_server
npm install
docker build -t mock-server:1.0.0 .
popd
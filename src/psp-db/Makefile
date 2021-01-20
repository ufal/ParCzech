IN=test-input
OUT=test-output

test: 
	./pspdb.sh -p $(IN)/person.xml -o $(OUT) -g $(IN) -c ../config.sh

stat: test
	echo "ORG ROLES"
	cat $(OUT)/org.xml |grep -o 'role="[^"]*"'|grep -o '".*"'|tr -d '"'|sort|uniq -c|sort -rn
	echo "PERSON ROLES"
	cat $(OUT)/person.xml |grep -o 'role="[^"]*"'|grep -o '".*"'|tr -d '"'|sort|uniq -c| sort -rn

clear:
	rm -r $(OUT)

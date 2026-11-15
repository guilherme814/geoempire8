#!/usr/bin/env python3
"""Gera data/leaders_1836.json: governantes por país (líder em 1836 + sucessores históricos).
Formato por linha: Nome|Título|ano|mês|cabelo|barba|chapéu
 cabelo: b castanho, k preto, g grisalho, w branco, r ruivo, y loiro, n calvo
 barba: none, stache, chops (suíças), full, goatee, long, f (mulher)
 chapéu: none, crown, bicorne, tophat, turban, fez, qing, eboshi, gat, mitre, ghutra, helmet, tiara, kepi, papakha, laurel
Dado estático: não entra no hash da simulação."""
import json, os

OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "data", "leaders_1836.json")

D = {}
def C(tag, skin, garb, text):
    L = []
    for ln in text.strip().splitlines():
        p = [x.strip() for x in ln.split("|")]
        name, title, y, m, hair, beard, hat = p
        L.append({"name": name, "title": title, "from": int(y), "m": int(m), "hair": hair, "beard": beard, "hat": hat})
    D[tag] = {"skin": skin, "garb": garb, "leaders": L}

C("GBR","light","uniform","""
Guilherme IV|Rei|1830|6|w|chops|crown
Vitória|Rainha|1837|6|b|f|tiara
Eduardo VII|Rei|1901|1|g|full|crown
Jorge V|Rei|1910|5|g|full|crown
Eduardo VIII|Rei|1936|1|y|none|crown
Jorge VI|Rei|1936|12|b|none|crown
Elizabeth II|Rainha|1952|2|b|f|tiara""")
C("FRA","light","uniform","""
Luís Filipe I|Rei dos Franceses|1830|8|g|chops|none
Luís Napoleão Bonaparte|Presidente da República|1848|12|b|stache|none
Napoleão III|Imperador|1852|12|b|goatee|none
Adolphe Thiers|Presidente da República|1871|8|g|none|none
Patrice de MacMahon|Presidente da República|1873|5|g|stache|kepi
Jules Grévy|Presidente da República|1879|1|g|chops|none
Sadi Carnot|Presidente da República|1887|12|b|full|none""")
C("RUS","light","uniform","""
Nicolau I|Imperador|1825|12|b|stache|helmet
Alexandre II|Imperador|1855|3|b|chops|helmet
Alexandre III|Imperador|1881|3|b|full|helmet
Nicolau II|Imperador|1894|11|b|goatee|helmet
Gueórgui Lvov|Chefe do Governo Provisório|1917|3|g|full|none
Alexander Kerensky|Chefe do Governo Provisório|1917|7|b|none|none
Vladimir Lênin|Presidente do Conselho|1917|11|n|goatee|none""")
C("PRU","light","uniform","""
Frederico Guilherme III|Rei|1797|11|g|chops|helmet
Frederico Guilherme IV|Rei|1840|6|b|chops|helmet
Guilherme I|Rei (Imperador Alemão em 1871)|1861|1|w|chops|helmet
Frederico III|Rei e Imperador|1888|3|b|full|helmet
Guilherme II|Rei e Imperador|1888|6|b|stache|helmet
Friedrich Ebert|Presidente|1919|2|b|stache|none
Paul von Hindenburg|Presidente|1925|5|w|stache|helmet""")
C("AUT","light","uniform","""
Fernando I|Imperador|1835|3|b|none|none
Francisco José I|Imperador|1848|12|b|chops|helmet
Carlos I|Imperador|1916|11|b|stache|helmet
Michael Hainisch|Presidente|1920|12|g|full|none
Wilhelm Miklas|Presidente|1928|12|g|stache|none""")
C("OTT","tan","robe","""
Mahmude II|Sultão|1808|7|k|full|fez
Abdulmecide I|Sultão|1839|7|k|stache|fez
Abdulaziz|Sultão|1861|6|k|full|fez
Murade V|Sultão|1876|5|k|full|fez
Abdulhamide II|Sultão|1876|8|g|long|fez
Maomé V|Sultão|1909|4|w|full|fez
Maomé VI|Sultão|1918|7|g|stache|fez""")
C("ESP","light","uniform","""
Isabel II|Rainha|1833|9|b|f|tiara
Amadeu I|Rei|1870|11|b|stache|none
Estanislao Figueras|Presidente da I República|1873|2|g|full|none
Afonso XII|Rei|1874|12|b|stache|none
Maria Cristina de Habsburgo|Rainha-regente|1885|11|b|f|tiara
Afonso XIII|Rei|1902|5|b|stache|none""")
C("POR","light","uniform","""
Maria II|Rainha|1834|5|b|f|tiara
Pedro V|Rei|1853|11|b|chops|none
Luís I|Rei|1861|11|b|full|none
Carlos I|Rei|1889|10|b|full|none
Manuel II|Rei|1908|2|b|stache|none
Manuel de Arriaga|Presidente|1911|8|w|full|none""")
C("NED","light","uniform","""
Guilherme I|Rei|1815|3|g|chops|none
Guilherme II|Rei|1840|10|b|chops|none
Guilherme III|Rei|1849|3|g|chops|none
Guilhermina|Rainha|1890|11|b|f|tiara
Juliana|Rainha|1948|9|b|f|tiara
Beatriz|Rainha|1980|4|b|f|tiara""")
C("BEL","light","uniform","""
Leopoldo I|Rei|1831|7|b|chops|none
Leopoldo II|Rei|1865|12|g|long|none
Alberto I|Rei|1909|12|y|stache|none
Leopoldo III|Rei|1934|2|b|none|none
Balduíno|Rei|1951|7|b|none|none
Alberto II|Rei|1993|8|g|none|none""")
C("SWE","light","uniform","""
Carlos XIV João|Rei|1818|2|w|none|none
Óscar I|Rei|1844|3|b|chops|none
Carlos XV|Rei|1859|7|b|stache|none
Óscar II|Rei|1872|9|b|full|none
Gustavo V|Rei|1907|12|g|stache|none
Gustavo VI Adolfo|Rei|1950|10|g|none|none
Carlos XVI Gustavo|Rei|1973|9|b|none|none""")
C("DEN","light","uniform","""
Frederico VI|Rei|1808|3|g|chops|none
Cristiano VIII|Rei|1839|12|g|chops|none
Frederico VII|Rei|1848|1|b|chops|none
Cristiano IX|Rei|1863|11|g|full|none
Frederico VIII|Rei|1906|1|g|full|none
Cristiano X|Rei|1912|5|g|stache|none
Frederico IX|Rei|1947|4|b|none|none""")
C("SAR","light","uniform","""
Carlos Alberto|Rei|1831|4|b|full|none
Vítor Emanuel II|Rei (Rei da Itália em 1861)|1849|3|b|stache|none
Humberto I|Rei da Itália|1878|1|b|stache|none
Vítor Emanuel III|Rei da Itália|1900|7|b|stache|none
Humberto II|Rei da Itália|1946|5|b|none|none""")
C("SIC","light","uniform","""
Fernando II|Rei das Duas Sicílias|1830|11|b|chops|none
Francisco II|Rei das Duas Sicílias|1859|5|b|none|none
Vítor Emanuel II|Rei da Itália|1861|3|b|stache|none
Humberto I|Rei da Itália|1878|1|b|stache|none
Vítor Emanuel III|Rei da Itália|1900|7|b|stache|none""")
C("PAP","light","robe","""
Gregório XVI|Papa|1831|2|w|none|mitre
Pio IX|Papa|1846|6|w|none|mitre
Leão XIII|Papa|1878|2|w|none|mitre
Pio X|Papa|1903|8|w|none|mitre
Bento XV|Papa|1914|9|g|none|mitre
Pio XI|Papa|1922|2|w|none|mitre
Pio XII|Papa|1939|3|w|none|mitre""")
C("TUS","light","uniform","""
Leopoldo II da Toscana|Grão-Duque|1824|7|b|chops|none
Fernando IV da Toscana|Grão-Duque|1859|7|b|none|none
Vítor Emanuel II|Rei da Itália|1861|3|b|stache|none
Humberto I|Rei da Itália|1878|1|b|stache|none
Vítor Emanuel III|Rei da Itália|1900|7|b|stache|none""")
C("BAV","light","uniform","""
Luís I da Baviera|Rei|1825|10|g|chops|none
Maximiliano II|Rei|1848|3|b|chops|none
Luís II|Rei|1864|3|k|stache|none
Luitpoldo|Príncipe-regente|1886|6|g|full|helmet
Luís III|Rei|1913|11|w|full|none
Kurt Eisner|Presidente do Conselho|1918|11|g|full|none""")
C("SAX","light","uniform","""
Antônio da Saxônia|Rei|1827|5|w|chops|none
Frederico Augusto II|Rei|1836|6|b|chops|none
João da Saxônia|Rei|1854|8|g|chops|none
Alberto da Saxônia|Rei|1873|10|g|full|helmet
Jorge da Saxônia|Rei|1902|10|w|full|none
Frederico Augusto III|Rei|1904|10|b|stache|none""")
C("HAN","light","uniform","""
Guilherme IV|Rei de Hanôver|1830|6|w|chops|none
Ernesto Augusto I|Rei de Hanôver|1837|6|w|stache|helmet
Jorge V de Hanôver|Rei de Hanôver|1851|11|b|stache|none
Guilherme I|Rei da Prússia|1866|10|w|chops|helmet
Frederico III|Rei da Prússia|1888|3|b|full|helmet
Guilherme II|Imperador Alemão|1888|6|b|stache|helmet""")
C("WUR","light","uniform","""
Guilherme I de Württemberg|Rei|1816|10|w|chops|none
Carlos I|Rei|1864|6|b|full|none
Guilherme II de Württemberg|Rei|1891|10|b|stache|none
Wilhelm Blos|Presidente|1918|11|g|full|none""")
C("HES","light","uniform","""
Luís II de Hesse|Grão-Duque|1830|4|g|chops|none
Luís III de Hesse|Grão-Duque|1848|6|b|chops|none
Luís IV de Hesse|Grão-Duque|1877|6|b|full|none
Ernesto Luís de Hesse|Grão-Duque|1892|3|b|stache|none""")
C("MEC","light","uniform","""
Frederico Francisco I|Grão-Duque|1785|4|w|chops|none
Paulo Frederico|Grão-Duque|1837|2|b|chops|none
Frederico Francisco II|Grão-Duque|1842|3|b|chops|none
Frederico Francisco III|Grão-Duque|1883|4|b|full|none
Frederico Francisco IV|Grão-Duque|1897|4|b|stache|none""")
C("THU","light","uniform","""
Carlos Frederico de Saxe-Weimar|Grão-Duque|1828|7|g|chops|none
Carlos Alexandre|Grão-Duque|1853|7|b|chops|none
Guilherme Ernesto|Grão-Duque|1901|1|b|stache|none""")
C("SUI","light","suit","""
Dieta Federal (Tagsatzung)|Presidência rotativa dos cantões|1815|9|g|chops|none
Jonas Furrer|Presidente da Confederação|1848|11|g|chops|none
Ulrich Ochsenbein|Presidente da Confederação|1849|1|b|full|none
Henri Druey|Presidente da Confederação|1850|1|g|chops|none
Josef Munzinger|Presidente da Confederação|1851|1|b|chops|none
Jonas Furrer|Presidente da Confederação|1852|1|g|chops|none
Friedrich Frey-Herosé|Presidente da Confederação|1853|1|g|chops|none""")
C("GRE","light","uniform","""
Otão I|Rei|1832|8|b|stache|none
Jorge I|Rei dos Helenos|1863|10|b|full|none
Constantino I|Rei|1913|3|b|full|none
Alexandre da Grécia|Rei|1917|6|b|none|none
Jorge II|Rei|1922|9|b|stache|none
Pavlos Kountouriotis|Presidente|1924|3|g|full|none""")
C("SER","light","uniform","""
Miloš Obrenović|Príncipe|1815|11|g|stache|papakha
Milan Obrenović II|Príncipe|1839|6|b|stache|papakha
Miguel Obrenović|Príncipe|1839|9|b|stache|none
Alexandre Karađorđević|Príncipe|1842|9|b|stache|none
Miloš Obrenović|Príncipe (retorno)|1858|12|w|stache|papakha
Miguel Obrenović|Príncipe (retorno)|1860|9|b|stache|none
Milan IV Obrenović|Príncipe e depois Rei|1868|7|b|full|none""")
C("VAL","light","robe","""
Alexandru II Ghica|Príncipe|1834|4|b|stache|papakha
Gheorghe Bibescu|Príncipe|1842|10|b|stache|papakha
Barbu Știrbei|Príncipe|1849|6|b|full|papakha
Alexandru Ioan Cuza|Príncipe dos Principados Unidos|1859|1|b|full|none
Carlos I da Romênia|Príncipe e depois Rei|1866|5|b|full|helmet
Fernando I da Romênia|Rei|1914|10|b|stache|none
Carlos II da Romênia|Rei|1930|6|b|stache|none""")
C("USA","light","suit","""
Andrew Jackson|Presidente|1829|3|g|none|none
Martin Van Buren|Presidente|1837|3|g|chops|none
William H. Harrison|Presidente|1841|3|g|none|none
John Tyler|Presidente|1841|4|g|none|none
James K. Polk|Presidente|1845|3|g|none|none
Zachary Taylor|Presidente|1849|3|g|none|none
Millard Fillmore|Presidente|1850|7|g|none|none""")
C("MEX","tan","uniform","""
Miguel Barragán|Presidente interino|1835|1|k|stache|bicorne
José Justo Corro|Presidente interino|1836|2|b|none|none
Anastasio Bustamante|Presidente|1837|4|k|stache|bicorne
Antonio López de Santa Anna|Presidente|1841|10|b|stache|bicorne
José Joaquín de Herrera|Presidente|1844|12|g|none|none
Mariano Paredes|Presidente|1846|1|b|stache|bicorne
Antonio López de Santa Anna|Presidente (retorno)|1846|12|g|stache|bicorne""")
C("CAM","tan","uniform","""
Francisco Morazán|Presidente da Federação|1830|9|k|stache|bicorne
Mariano Rivera Paz|Chefe de Estado|1839|4|b|stache|none
Rafael Carrera|Presidente|1844|12|k|none|none
Vicente Cerna|Presidente|1865|5|b|stache|none
Justo Rufino Barrios|Presidente|1873|6|k|stache|kepi
Manuel Lisandro Barillas|Presidente|1885|6|b|stache|none
Manuel Estrada Cabrera|Presidente|1898|2|b|stache|none""")
C("HAI","dark","uniform","""
Jean-Pierre Boyer|Presidente|1818|3|k|none|bicorne
Charles Rivière-Hérard|Presidente|1843|3|k|stache|bicorne
Philippe Guerrier|Presidente|1844|5|w|none|bicorne
Faustin Soulouque|Presidente (Imperador Faustino I)|1847|3|k|none|crown
Fabre Geffrard|Presidente|1859|1|g|chops|bicorne
Sylvain Salnave|Presidente|1867|6|k|stache|bicorne""")
C("NGR","tan","uniform","""
Francisco de Paula Santander|Presidente|1832|10|g|none|none
José Ignacio de Márquez|Presidente|1837|4|g|none|none
Pedro Alcântara Herrán|Presidente|1841|4|k|none|none
Tomás Cipriano de Mosquera|Presidente|1845|4|k|chops|none
José Hilario López|Presidente|1849|4|g|chops|none
José María Obando|Presidente|1853|4|g|chops|none
Manuel María Mallarino|Presidente|1855|4|g|chops|none""")
C("VEN","tan","uniform","""
José María Vargas|Presidente|1835|2|g|none|none
Carlos Soublette|Presidente|1837|1|g|stache|none
José Antonio Páez|Presidente|1839|3|k|chops|bicorne
Carlos Soublette|Presidente (retorno)|1843|1|g|stache|none
José Tadeo Monagas|Presidente|1847|1|g|chops|none
José Gregorio Monagas|Presidente|1851|1|g|stache|none
Julián Castro|Presidente|1858|3|b|stache|none""")
C("ECU","tan","uniform","""
Vicente Rocafuerte|Presidente|1835|8|k|none|none
Juan José Flores|Presidente|1839|1|k|chops|bicorne
Vicente Ramón Roca|Presidente|1845|12|k|chops|none
Diego Noboa|Presidente|1850|2|g|none|none
José María Urvina|Presidente|1852|7|b|stache|bicorne
Francisco Robles|Presidente|1856|9|k|chops|none
Gabriel García Moreno|Presidente|1861|1|k|chops|none""")
C("PER","tan","uniform","""
Luis José de Orbegoso|Presidente|1834|12|k|chops|bicorne
Andrés de Santa Cruz|Protetor da Confederação|1836|10|k|none|bicorne
Agustín Gamarra|Presidente|1839|8|k|stache|bicorne
Ramón Castilla|Presidente|1845|4|g|stache|bicorne
José Rufino Echenique|Presidente|1851|4|k|stache|none
Ramón Castilla|Presidente (retorno)|1855|1|g|stache|bicorne""")
C("BOL","tan","uniform","""
Andrés de Santa Cruz|Presidente|1829|5|k|none|bicorne
José Miguel de Velasco|Presidente|1839|2|k|stache|bicorne
Manuel Isidoro Belzu|Presidente|1848|12|k|stache|bicorne
Jorge Córdova|Presidente|1855|8|k|stache|none
José María Linares|Presidente|1857|9|k|none|none
Mariano Melgarejo|Presidente|1864|12|k|stache|bicorne
Agustín Morales|Presidente|1871|1|k|stache|bicorne""")
C("BRZ","light","uniform","""
Diogo Feijó|Regente Uno|1835|10|g|none|none
Pedro de Araújo Lima|Regente|1837|9|g|chops|none
Pedro II|Imperador|1840|7|y|none|crown
Deodoro da Fonseca|Presidente|1889|11|w|full|kepi
Floriano Peixoto|Presidente|1891|11|k|chops|kepi
Prudente de Morais|Presidente|1894|11|g|full|none
Campos Sales|Presidente|1898|11|g|full|none""")
C("ARG","light","uniform","""
Juan Manuel de Rosas|Governador de Buenos Aires|1835|4|y|chops|none
Justo José de Urquiza|Presidente da Confederação|1854|3|b|chops|none
Santiago Derqui|Presidente|1860|3|g|chops|none
Bartolomé Mitre|Presidente|1862|10|g|full|none
Domingo Sarmiento|Presidente|1868|10|g|stache|none
Nicolás Avellaneda|Presidente|1874|10|k|stache|none
Julio Argentino Roca|Presidente|1880|10|b|full|none""")
C("URU","light","uniform","""
Manuel Oribe|Presidente|1835|3|b|chops|none
Fructuoso Rivera|Presidente|1838|10|b|chops|none
Joaquín Suárez|Chefe de Governo|1843|2|g|chops|none
Juan Francisco Giró|Presidente|1852|3|b|chops|none
Venancio Flores|Governador provisório|1854|9|k|stache|none
Gabriel Pereira|Presidente|1856|3|g|chops|none
Bernardo Berro|Presidente|1860|3|g|chops|none""")
C("PAR","tan","uniform","""
José Gaspar Rodríguez de Francia|Ditador Perpétuo|1814|6|g|none|tophat
Carlos Antonio López|Presidente|1844|3|g|chops|none
Francisco Solano López|Presidente|1862|9|k|full|kepi
Cirilo Antonio Rivarola|Presidente|1870|8|b|chops|none
Salvador Jovellanos|Presidente|1871|12|g|chops|none
Juan Bautista Gill|Presidente|1874|11|b|stache|none
Cándido Bareiro|Presidente|1878|11|g|chops|none""")
C("CHL","light","uniform","""
Joaquín Prieto|Presidente|1831|9|g|none|none
Manuel Bulnes|Presidente|1841|9|b|stache|bicorne
Manuel Montt|Presidente|1851|9|b|stache|none
José Joaquín Pérez|Presidente|1861|9|g|chops|none
Federico Errázuriz Zañartu|Presidente|1871|9|g|stache|none
Aníbal Pinto|Presidente|1876|9|b|stache|none
Domingo Santa María|Presidente|1881|9|g|full|none""")
C("HAW","brown","uniform","""
Kamehameha III|Rei|1825|6|k|none|crown
Kamehameha IV|Rei|1854|12|k|stache|crown
Kamehameha V|Rei|1863|11|k|stache|crown
Lunalilo|Rei|1873|1|k|chops|crown
Kalākaua|Rei|1874|2|k|stache|crown
Liliʻuokalani|Rainha|1891|1|k|f|tiara
Sanford Dole|Presidente da República|1894|7|g|stache|none""")
C("QNG","east","qing","""
Daoguang|Imperador|1820|9|k|none|qing
Xianfeng|Imperador|1850|3|k|stache|qing
Tongzhi|Imperador|1861|11|k|none|qing
Guangxu|Imperador|1875|2|k|none|qing
Puyi (Xuantong)|Imperador|1908|11|k|none|qing
Sun Yat-sen|Presidente Provisório|1912|1|k|stache|none
Yuan Shikai|Presidente|1912|3|k|stache|helmet""")
C("JAP","east","kimono","""
Tokugawa Ienari|Xogum|1787|4|g|none|eboshi
Tokugawa Ieyoshi|Xogum|1837|4|k|none|eboshi
Tokugawa Iesada|Xogum|1853|11|k|none|eboshi
Tokugawa Iemochi|Xogum|1858|10|k|none|eboshi
Tokugawa Yoshinobu|Xogum|1866|12|k|none|eboshi
Meiji|Imperador|1868|1|k|stache|eboshi
Taishō|Imperador|1912|7|k|stache|helmet""")
C("KOR","east","kimono","""
Heonjong|Rei|1834|12|k|none|gat
Cheoljong|Rei|1849|6|k|none|gat
Gojong|Rei (Imperador em 1897)|1863|12|k|stache|gat
Sunjong|Imperador|1907|7|k|stache|gat
Syngman Rhee|Presidente|1948|8|w|none|none
Yun Posun|Presidente|1960|8|g|stache|none""")
C("VNM","east","kimono","""
Minh Mạng|Imperador|1820|2|k|goatee|gat
Thiệu Trị|Imperador|1841|1|k|goatee|gat
Tự Đức|Imperador|1847|11|k|goatee|gat
Hàm Nghi|Imperador|1884|8|k|none|gat
Đồng Khánh|Imperador|1885|9|k|none|gat
Thành Thái|Imperador|1889|1|k|none|gat
Duy Tân|Imperador|1907|9|k|none|gat""")
C("SIA","brown","robe","""
Nangklao (Rama III)|Rei|1824|7|k|none|crown
Mongkut (Rama IV)|Rei|1851|4|k|none|crown
Chulalongkorn (Rama V)|Rei|1868|10|k|stache|crown
Vajiravudh (Rama VI)|Rei|1910|10|k|stache|crown
Prajadhipok (Rama VII)|Rei|1925|11|k|stache|crown
Ananda Mahidol (Rama VIII)|Rei|1935|3|k|none|crown
Bhumibol Adulyadej (Rama IX)|Rei|1946|6|k|none|crown""")
C("BUR","brown","robe","""
Bagyidaw|Rei|1819|4|k|none|crown
Tharrawaddy|Rei|1837|4|k|none|crown
Pagan Min|Rei|1846|11|k|none|crown
Mindon|Rei|1853|2|k|none|crown
Thibaw|Rei|1878|10|k|none|crown""")
C("IRN","tan","robe","""
Maomé Xá Qajar|Xá|1834|10|k|full|papakha
Nasereddin Xá|Xá|1848|9|k|stache|papakha
Mozaffareddin Xá|Xá|1896|5|k|stache|papakha
Mohammad Ali Xá|Xá|1907|1|k|stache|papakha
Ahmad Xá|Xá|1909|7|k|none|papakha
Reza Xá Pahlavi|Xá|1925|12|k|stache|kepi
Mohammad Reza Pahlavi|Xá|1941|9|k|stache|kepi""")
C("AFG","tan","robe","""
Dost Mohammad Khan|Emir|1826|10|k|long|turban
Xá Shuja|Rei (imposto pelos britânicos)|1839|8|k|long|turban
Dost Mohammad Khan|Emir (retorno)|1843|4|g|long|turban
Sher Ali Khan|Emir|1863|6|k|full|turban
Abdur Rahman Khan|Emir|1880|7|k|full|turban
Habibullah Khan|Emir|1901|10|k|full|turban
Amanullah Khan|Emir e depois Rei|1919|2|k|stache|kepi""")
C("NEP","brown","robe","""
Rajendra Bikram Shah|Rei|1816|11|k|stache|crown
Surendra Bikram Shah|Rei|1847|5|k|stache|crown
Prithvi Bir Bikram Shah|Rei|1881|5|k|stache|crown
Tribhuvan|Rei|1911|12|k|stache|crown
Mahendra|Rei|1955|3|k|none|crown
Birendra|Rei|1972|1|k|none|crown""")
C("BIC","light","uniform","""
Sir Charles Metcalfe|Governador-Geral interino|1835|3|g|none|none
Lord Auckland|Governador-Geral|1836|3|g|none|none
Lord Ellenborough|Governador-Geral|1842|2|b|none|none
Lord Hardinge|Governador-Geral|1844|7|g|stache|bicorne
Lord Dalhousie|Governador-Geral|1848|1|g|chops|none
Lord Canning|Governador-Geral e depois Vice-Rei|1856|2|g|chops|none""")
C("SIK","brown","robe","""
Ranjit Singh|Marajá (Leão do Panjabe)|1801|4|g|long|turban
Kharak Singh|Marajá|1839|6|k|full|turban
Nau Nihal Singh|Marajá|1840|11|k|stache|turban
Sher Singh|Marajá|1841|1|k|long|turban
Duleep Singh|Marajá|1843|9|k|none|turban""")
C("SND","tan","robe","""
Mir Nur Muhammad Talpur|Emir de Hyderabad (Sind)|1830|1|g|full|turban
Mir Nasir Khan Talpur|Emir de Hyderabad (Sind)|1840|1|g|full|turban
Charles Napier|Governador de Sind|1843|2|g|stache|none""")
C("HYD","brown","robe","""
Nasir-ud-Daulah|Nizam|1829|5|k|full|turban
Afzal ad-Daulah|Nizam|1857|5|k|full|turban
Mir Mahbub Ali Khan|Nizam|1869|2|k|stache|turban
Mir Osman Ali Khan|Nizam|1911|8|k|stache|fez""")
C("MYS","brown","robe","""
Krishnaraja Wodeyar III|Marajá|1799|6|g|stache|turban
Chamarajendra Wadiyar X|Marajá|1881|3|k|stache|turban
Krishnaraja Wadiyar IV|Marajá|1895|2|k|stache|turban
Jayachamaraja Wadiyar|Marajá|1940|8|k|stache|turban""")
C("TRV","brown","robe","""
Swathi Thirunal|Marajá|1829|4|k|stache|turban
Uthram Thirunal|Marajá|1846|12|k|stache|turban
Ayilyam Thirunal|Marajá|1860|10|k|stache|turban
Visakham Thirunal|Marajá|1880|5|k|stache|turban
Moolam Thirunal|Marajá|1885|8|k|stache|turban
Chithira Thirunal|Marajá|1931|9|k|stache|turban""")
C("RAJ","brown","robe","""
Ram Singh II de Jaipur|Marajá|1835|2|k|none|turban
Madho Singh II|Marajá|1880|9|k|stache|turban
Man Singh II|Marajá|1922|9|k|stache|turban""")
C("MAR","brown","robe","""
Janakoji Rao Scindia|Marajá de Gwalior|1827|3|k|stache|turban
Jayajirao Scindia|Marajá de Gwalior|1843|2|k|stache|turban
Madho Rao Scindia|Marajá de Gwalior|1886|6|k|stache|turban
Jivajirao Scindia|Marajá de Gwalior|1925|6|k|stache|turban""")
C("MAL","brown","robe","""
Shahabuddin Riayat Shah|Sultão de Perak|1830|1|k|stache|turban
Abdul Malik Mansur Shah|Sultão de Perak|1851|1|k|stache|turban
Ja'afar Safiuddin|Sultão de Perak|1857|1|k|stache|turban
Ali Al-Mukammal|Sultão de Perak|1865|1|k|stache|turban
Abdullah Muhammad Shah II|Sultão de Perak|1874|1|k|stache|turban
Idris Murshidul Azam Shah|Sultão de Perak|1887|1|k|stache|turban""")
C("BRU","brown","robe","""
Omar Ali Saifuddin II|Sultão|1829|1|k|stache|turban
Abdul Momin|Sultão|1852|5|k|stache|turban
Hashim Jalilul Alam|Sultão|1885|1|k|stache|turban
Muhammad Jamalul Alam II|Sultão|1906|5|k|stache|turban
Ahmad Tajuddin II|Sultão|1924|9|k|stache|turban
Omar Ali Saifuddien III|Sultão|1950|6|k|stache|turban""")
C("ACE","brown","robe","""
Muhammad Syah|Sultão|1823|1|k|stache|turban
Sulaiman Ali Iskandar Syah|Sultão|1838|1|k|stache|turban
Mansur Syah|Sultão|1857|1|k|stache|turban
Mahmud Syah|Sultão|1870|1|k|stache|turban
Muhammad Daud Syah|Sultão|1874|1|k|none|turban""")
C("EGY","tan","robe","""
Maomé Ali|Paxá e Vice-Rei|1805|7|w|full|fez
Abbas I|Paxá|1848|11|k|stache|fez
Said Paxá|Paxá|1854|7|k|stache|fez
Ismail Paxá|Quediva|1863|1|k|full|fez
Tewfik Paxá|Quediva|1879|6|k|stache|fez
Abbas II Hilmi|Quediva|1892|1|k|stache|fez""")
C("NAJ","tan","arab","""
Faisal bin Turki|Emir|1834|6|k|full|ghutra
Khalid bin Saud|Emir|1838|1|k|full|ghutra
Abdullah bin Thunayyan|Emir|1841|1|k|full|ghutra
Faisal bin Turki|Emir (retorno)|1843|1|g|full|ghutra
Abdullah bin Faisal|Emir|1865|12|k|full|ghutra
Saud bin Faisal|Emir|1871|1|k|full|ghutra""")
C("OMA","tan","arab","""
Said bin Sultan|Sultão|1806|1|k|full|turban
Thuwaini bin Said|Sultão|1856|10|k|full|turban
Salim bin Thuwaini|Sultão|1866|1|k|full|turban
Turki bin Said|Sultão|1871|1|k|full|turban
Faisal bin Turki|Sultão|1888|1|k|full|turban
Taimur bin Faisal|Sultão|1913|10|k|stache|turban""")
C("KHI","tan","robe","""
Allah Quli Khan|Cã de Khiva|1825|1|k|full|papakha
Rahim Quli Khan|Cã de Khiva|1842|1|k|full|papakha
Muhammad Amin Khan|Cã de Khiva|1845|1|k|full|papakha
Abdullah Khan|Cã de Khiva|1855|1|k|full|papakha
Sayyid Muhammad Rahim II|Cã de Khiva|1864|1|k|full|papakha
Isfandiyar Khan|Cã de Khiva|1910|1|k|stache|papakha""")
C("BUK","tan","robe","""
Nasrullah Khan|Emir de Bucara|1827|1|k|full|turban
Muzaffar al-Din|Emir de Bucara|1860|1|k|full|turban
Abdulahad Khan|Emir de Bucara|1885|1|k|full|turban
Alim Khan|Emir de Bucara|1910|1|k|stache|turban""")
C("KOK","tan","robe","""
Muhammad Ali Khan (Madali)|Cã de Kokand|1822|1|k|full|turban
Shir Ali Khan|Cã de Kokand|1842|1|k|full|turban
Khudayar Khan|Cã de Kokand|1845|1|k|full|turban
Malla Khan|Cã de Kokand|1858|1|k|full|turban
Khudayar Khan|Cã de Kokand (retorno)|1862|1|k|full|turban
Nasriddin Khan|Cã de Kokand|1875|1|k|stache|turban""")
C("MOR","tan","robe","""
Abderramão de Marrocos|Sultão|1822|11|g|full|turban
Maomé IV|Sultão|1859|8|k|full|turban
Hassan I|Sultão|1873|9|k|stache|turban
Abdelaziz|Sultão|1894|6|k|none|turban
Abdelhafid|Sultão|1908|8|k|stache|turban
Iúçufe de Marrocos|Sultão|1912|8|k|stache|turban""")
C("TUN","tan","robe","""
Hussein II Bey|Bei de Túnis|1824|1|g|full|fez
Mustafa Bey|Bei de Túnis|1835|10|k|stache|fez
Ahmad I Bey|Bei de Túnis|1837|10|k|full|fez
Muhammad Bey|Bei de Túnis|1855|5|k|full|fez
Muhammad as-Sadiq Bey|Bei de Túnis|1859|9|k|full|fez
Ali III Bey|Bei de Túnis|1882|10|k|stache|fez
Muhammad al-Hadi Bey|Bei de Túnis|1902|6|k|stache|fez""")
C("ETH","dark","robe","""
Sahle Dengel|Imperador (Negus)|1832|1|k|stache|none
Tewodros II|Imperador|1855|2|k|stache|none
Yohannes IV|Imperador|1872|1|k|full|none
Menelik II|Imperador|1889|1|k|stache|none
Iyasu V|Imperador (não coroado)|1913|12|k|none|none
Zauditu|Imperatriz|1916|9|k|f|tiara
Haile Selassie I|Imperador|1930|4|k|goatee|none""")
C("SOK","dark","arab","""
Muhammad Bello|Sultão de Sokoto|1817|1|k|full|turban
Abu Bakr Atiku|Sultão de Sokoto|1837|10|k|full|turban
Aliyu Karami|Sultão de Sokoto|1842|10|k|full|turban
Ahmadu Atiku|Sultão de Sokoto|1859|1|k|full|turban
Ahmadu Rufai|Sultão de Sokoto|1866|1|k|full|turban""")
C("ZUL","dark","african","""
Dingane|Rei dos Zulus|1828|9|k|none|none
Mpande|Rei dos Zulus|1840|2|k|none|none
Cetshwayo|Rei dos Zulus|1872|9|k|none|none
Dinuzulu|Rei dos Zulus|1884|5|k|none|none""")
C("MAD","brown","robe","""
Ranavalona I|Rainha|1828|8|k|f|tiara
Radama II|Rei|1861|8|k|none|crown
Rasoherina|Rainha|1863|5|k|f|tiara
Ranavalona II|Rainha|1868|4|k|f|tiara
Ranavalona III|Rainha|1883|7|k|f|tiara""")
C("ABD","tan","arab","""
Abd al-Qadir al-Jaza'iri|Emir|1832|11|k|full|turban""")
C("TEX","light","suit","""
Henry Smith|Governador provisório|1835|11|g|none|none
David G. Burnet|Presidente interino|1836|3|b|chops|none
Sam Houston|Presidente|1836|10|b|none|none
Mirabeau B. Lamar|Presidente|1838|12|b|stache|none
Sam Houston|Presidente (retorno)|1841|12|g|stache|none
Anson Jones|Presidente|1844|12|b|none|none
J. Pinckney Henderson|Governador|1846|2|b|none|none""")
C("CAU","tan","robe","""
Imã Shamil|Imã do Daguestão e da Chechênia|1834|10|g|full|papakha""")
C("MNE","light","robe","""
Petar II Petrović-Njegoš|Príncipe-bispo|1830|10|k|stache|papakha
Danilo I|Príncipe|1851|10|k|stache|papakha
Nikola I|Príncipe e depois Rei|1860|8|k|stache|papakha""")

json.dump(D, open(OUT, "w", encoding="utf-8"), ensure_ascii=False, indent=1)
print("países:", len(D), "líderes:", sum(len(v["leaders"]) for v in D.values()))

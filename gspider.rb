# encoding: utf-8

#!/usr/bin/env ruby
require 'pp'
require './httpmodule.rb'
require 'rkelly'
require 'domainatrix'

include HttpModule

$apps = [
	{name:"hanweb", htmlcontent:[]}
]

#host带有端口号
$hosts = []
$allow_hosts = []

def allow_host?(host)
	rootdomain = rootdomain_of_host host
	$allow_hosts.select{|h| host.include?(h)}.size>0
end

def get_domain_info_by_host(host)
	url = Domainatrix.parse(host)
	if url.domain && url.public_suffix
		return url
	end
	nil
end

def host_of_url(url)
	url = 'http://'+url+'/' if !url.include?('http://') and !url.include?('https://')
	url = URI.encode(url) unless url.include? '%' #如果包含百分号%，说明已经编码过了
	uri = URI(url)
	uri.host
end

def hostinfo_of_url(url)
	url = 'http://'+url+'/' if !url.include?('http://') and !url.include?('https://')
	url = URI.encode(url) unless url.include? '%' #如果包含百分号%，说明已经编码过了
	uri = URI(url)
	uri.host+':'+uri.port.to_s
end

def hosthomepage_of_url(url)
	url = 'http://'+url+'/' if !url.include?('http://') and !url.include?('https://')
	url = URI.encode(url) unless url.include? '%' #如果包含百分号%，说明已经编码过了
	uri = URI(url)
	uri.scheme+"://"+uri.host+':'+uri.port.to_s
end

def join_url(url, refer)
	#puts url,refer
	url = URI.encode(url) unless url.include? '%' #如果包含百分号%，说明已经编码过了
	begin
		u = URI.join(refer, url)
		u.to_s
	rescue => e
		puts "join_url failed of : #{url} #{refer}" #zhushou360:// thunder://等协议
		nil
	end
end

def rootdomain_of_host(host)
	domain_info = get_domain_info_by_host(host)
	domain = domain_info.domain+'.'+domain_info.public_suffix
end

def get_host(hosts)
	hosts.each{ |h|
		return h if h[:state] == 0
	}
	return nil
end

def host_exists?(host)
	$hosts.select{|h| host.include?(h[:host])}.size>0
end

def get_redirect_url(html)
	return nil unless html
	if html.include?('window.open')
		url = html[/window.open\((.+),/is, 1].gsub(/['"]/, '')
	elsif html.include?('window.location.href')
		url = html[/window.location.href[\s]*=[\s]*(.+)[;\s]/is, 1].gsub(/['"]/, '')
	end
	url
end

def process_host(h)
	pp h
	h[:state] = 1

	http = load_info(h[:homepage])
	if http[:error]
		puts 'http request failed of : '+h[:homepage]
		h[:state] = 2
		return false
	end

	doc = Nokogiri::HTML(http[:utf8html])
	meta_refresh = doc.at('meta[http-equiv="Refresh"]')
	meta_refresh ||= doc.at('meta[http-equiv="refresh"]')
	meta_refresh ||= doc.at('meta[http-equiv="REFRESH"]')
	if meta_refresh
		url = meta_refresh['content'][/url=(.+)/is, 1].gsub(/['"]/, '')
		if url
			pp url
			h[:homepage] = join_url(url.strip, h[:homepage])
			h[:state] = 0
			return true
		end
	end
	
	doc.xpath('//a[@href]').each do |link|
	  	unless link['href'].include?'javascript:'
	  		url = join_url(link['href'].strip, h[:homepage])
	  		if url
		  		host = host_of_url(url)
		  		if allow_host?(host)
		  			h[:links] << url  
		  			$hosts << {host:host, homepage:hosthomepage_of_url(url), state:0, links:[], css:[], js:[], jsvar:[], html:nil, header:nil, status:nil, webapp:[]} unless host_exists?(host)
		  		end
		  	end
	  	end
	end
	doc.xpath('//link[@href]').each do |link|
	  h[:css] << join_url(link['href'].strip, h[:homepage])
	end
	doc.xpath('//script[@src]').each do |link|
	  h[:js] << join_url(link['src'].strip, h[:homepage])
	end

	parser = RKelly::Parser.new
	doc.css('script').each do |script|
		begin
			if !script['type'] || !script['type'][/text\/html/is]
				ast = parser.parse(script.content)
				if ast 
					ast.each {|n|
						if n.class == RKelly::Nodes::VarDeclNode
							if n.name.size>4
								h[:jsvar] << n.name
							end
						end
					}
				end
			end
		
		rescue => e
			puts 'javascript parse failed of : '+h[:homepage]
		end
	end

	if h[:css].size<1 && h[:js].size<1 && h[:links].size<1 
		url = get_redirect_url(http[:utf8html])
		if url
			pp url
			h[:homepage] = join_url(url.strip, h[:homepage])
			h[:state] = 0
			return true
		end
	end
	h[:html] = http[:utf8html]
	h[:status] = http[:code]
	header = []
	http[:header].each_capitalized() {|k, v| #if !r[:error]
      header << [k,v].join(': ')
    }
    header = header.join("\n").force_encoding('UTF-8')
	h[:header] = header
	
	h[:state] = 2
	#pp h
end

def main(argv)
	#pp argv
	#host include port like abc.com:80, state means process step:0 is initialized, 1 is processing, 2 is finished
	url = argv[0]
	url = 'http://'+url+'/' if !url.include?('http://') and !url.include?('https://')
	host = host_of_url(url)
	$hosts << {host:host, homepage:url, state:0, links:[], css:[], js:[], jsvar:[], html:nil, header:nil, status:nil, webapp:[]}
	$allow_hosts << "."+rootdomain_of_host(host)

	while true
		h = get_host($hosts)
		break unless h
		process_host(h)
		#sleep 1 if get_host($hosts)
	end
end

puts hostinfo_of_url('http://abc.com:1234/')
main(ARGV)